class TaskScheduler
	def self.pending_task
		# 分配今日资源
		Account.active.where(work_type:0).each do |account|
			task = MoveTask.where(status:"pending").where(platform:account.platform,theme:account["theme"]).order("created_at asc").first
			if !task.nil?
				task.update(account_id: account.id,browser_id: account.browser_id,status:"waiting_publish")
			end
		end
	end

	def self.assign_resources(platform: nil)
		logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'taskscheduler_assignresources.log'))
		logger.formatter = Rails.logger.formatter
		Rails.logger = logger

		today = Date.today
		today_start = today.beginning_of_day
		today_end = today.end_of_day

		resource_configs = [
			{ work_type: "视频搬运", task_model: MoveTask, type_name: "搬运" },
			{ work_type: "人工运营", task_model: OperationTask, type_name: "运营" },
			{ work_type: "Grok", task_model: GrokTask, type_name: "Grok" },
			# { work_type: "Heygen", task_model: HeygenTask, type_name: "Heygen" },
			{ work_type: "剪映", task_model: JianyingTask, type_name: "剪映" },
			{ work_type: "花生", task_model: HuashengTask, type_name: "花生" },
			{ work_type: "Notebooklm", task_model: NotebooklmTask, type_name: "Notebooklm" }
		]

		resource_configs.each do |config|
			begin
				accounts = Account.active.where(work_type: config[:work_type])
				accounts = accounts.where(platform: platform) if platform.present?

				accounts.each do |account|
					task_model = config[:task_model]
					type_name = config[:type_name]

					has_posted_today = task_model.exists?(
						account_id: account.id,
						status: :success,
						actual_publish_time: today_start..today_end
					)

					next if has_posted_today

					# TikTok 限制：账号过去3天发文浏览量均为0时暂停分配，冷却3天后再恢复
					# （滑动窗口：连续0浏览量的账号会被持续跳过，直到窗口滑出那些0浏览量的发文）
					if platform == 'tiktok' && account.zero_views_in_past_3_days?
						Rails.logger.info "TikTok账号 #{account.account_name}[#{account.platform}-#{account.theme}] 过去3天发文浏览量均为0，暂停3天后再分配资源"
						next
					end

					pending_task = task_model.where(status: :pending, platform: account.platform, theme: account.theme).order(created_at: :asc).first

					if pending_task
						ActiveRecord::Base.transaction do
							pending_task.update!(
								account_id: account.id,
								browser_id: account.browser_id,
								status: :waiting_publish
							)
						end
						Rails.logger.info "#{type_name}账号 #{account.account_name}[#{account.platform}-#{account.theme}] 分配 #{type_name} 资源成功"
					else
						Rails.logger.warn "#{type_name}账号 #{account.account_name}[#{account.platform}-#{account.theme}] 暂无可用 #{type_name} 资源"
					end
				end
			rescue => e
				Rails.logger.error "[TaskScheduler] 处理 #{config[:type_name]} 资源分配时发生异常: #{e.message}"
				Rails.logger.error "[TaskScheduler] 异常堆栈: #{e.backtrace.join("\n")}"
			end
		end

		TaskScheduler.find_locked_browsers_in_pending_tasks
	end

	# 找出待执行任务中与锁定接口重合的指纹浏览器名称
	# 遍历所有运营机器（browser.machine_ip）查询锁定状态，避免遗漏其他机器上的锁
	def self.find_locked_browsers_in_pending_tasks

		# 1. 获取待执行任务中的指纹浏览器
		pending_browser_ids = []

		# 从搬运任务中获取
		pending_browser_ids += MoveTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从运营任务中获取
		pending_browser_ids += OperationTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从 Grok 任务中获取
		pending_browser_ids += GrokTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从 Heygen 任务中获取
		pending_browser_ids += HeygenTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从剪映任务中获取
		pending_browser_ids += JianyingTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从花生任务中获取
		pending_browser_ids += HuashengTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从 Notebooklm 任务中获取
		pending_browser_ids += NotebooklmTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 获取待发布浏览器及其所属机器 IP（用于遍历每台机器查询锁定）
		pending_browsers = Browser.where(id: pending_browser_ids.uniq)
		pending_browser_names = pending_browsers.pluck(:profile_name).uniq

		return { pending_browsers: pending_browser_names, locked_browsers: [], matched_browsers: [] } if pending_browser_names.empty?

		# 待发布任务覆盖的运营机器 IP；同时遍历所有运营机器以发现跨机器的锁
		machine_ips = Browser.where.not(machine_ip: [nil, ""]).distinct.pluck(:machine_ip).sort

		if machine_ips.empty?
			Rails.logger.warn "[TaskScheduler] 暂无已配置 machine_ip 的运营机器，无法查询锁定状态"
			return { pending_browsers: pending_browser_names, locked_browsers: [], matched_browsers: [] }
		end

		# 2. 遍历每台运营机器调用锁定接口，合并锁定列表
		locked_browser_names = []
		machine_errors = []

		machine_ips.each do |ip|
			begin
				names = fetch_locked_browser_names(ip)
				locked_browser_names.concat(names)
				Rails.logger.info "[TaskScheduler] 机器 #{ip} 返回 #{names.size} 个锁定浏览器"
			rescue => e
				machine_errors << "#{ip}: #{e.message}"
				Rails.logger.error "[TaskScheduler] 调用机器 #{ip} 锁定接口失败: #{e.message}"
			end
		end

		locked_browser_names.uniq!

		# 3. 找出重合的浏览器名称
		matched_browser_names = pending_browser_names & locked_browser_names

		# 4. 如果有匹配的浏览器，发送钉钉通知
		if matched_browser_names.present?
			send_locked_browsers_alert(matched_browser_names, pending_browser_names, locked_browser_names)
		end

		result = {
			pending_browsers: pending_browser_names,
			locked_browsers: locked_browser_names,
			matched_browsers: matched_browser_names
		}
		result[:machine_errors] = machine_errors if machine_errors.any?
		result
	end

	# 调用单台运营机器的锁定接口，返回锁定的浏览器名称数组
	# 端点：http://<machine_ip>:8080/api/browser/locked（端口固定 8080）
	def self.fetch_locked_browser_names(machine_ip)
		uri = URI("http://#{machine_ip}:8080/api/browser/locked")
		http = Net::HTTP.new(uri.host, uri.port)
		http.open_timeout = 100
		http.read_timeout = 100

		response = http.get(uri.path)
		locked_data = JSON.parse(response.body)

		if locked_data.is_a?(Array)
			locked_data.map { |item| item['name'] || item[:name] }.compact
		elsif locked_data.is_a?(Hash) && locked_data['data'].is_a?(Array)
			locked_data['data'].map { |item| item['name'] || item[:name] }.compact
		else
			[]
		end
	end

	# 发送钉钉告警消息
	def self.send_locked_browsers_alert(matched_browsers, pending_browsers, locked_browsers)
		require 'net/http'
		require 'json'

		webhook_url = ENV['DINGDING_WEBHOOK_URL']
		return unless webhook_url.present?

		# 格式化浏览器列表
		matched_list = matched_browsers.map { |name| "• #{name}" }.join("\n")
		pending_list = pending_browsers.map { |name| "• #{name}" }.join("\n")
		locked_list = locked_browsers.map { |name| "• #{name}" }.join("\n")

		message = "【发布】检测到被锁定的浏览器正在执行任务\n\n"
		message += "🔒 被锁定的浏览器（共 #{matched_browsers.size} 个）：\n#{matched_list}\n\n"
		message += "📋 待执行任务中的浏览器（共 #{pending_browsers.size} 个）：\n#{pending_list}\n\n"
		message += "⏰ 检测时间：#{Time.current.strftime("%Y-%m-%d %H:%M:%S")}"

		webhook_url = ENV['DINGDING_WEBHOOK_URL']
		return unless webhook_url.present?

		postbody = {"msgtype": "text","text": {"content": message}}
		headers = {
			"Content-Type": "application/json;charset=utf-8"
		}
		res = RestClient.post(webhook_url,postbody.to_json,headers = headers)
	end

	# 检查前两小时内"指纹浏览器已被占用"错误，并发送钉钉通知
	def self.check_browser_occupied_errors
		two_hours_ago = 2.hours.ago

		# 查询前两小时内包含"指纹浏览器已被占用"的错误日志
		error_logs = TaskLog.where("error_msg LIKE ? AND created_at >= ?", "%指纹浏览器已被占用%", two_hours_ago)
		                    .where.not(browser_id: nil)

		# 获取浏览器名称并去重
		browser_ids = error_logs.pluck(:browser_id).compact.uniq
		browsers = Browser.where(id: browser_ids).pluck(:profile_name).compact.uniq

		return if browsers.empty?

		# 发送钉钉通知
		send_browser_occupied_alert(browsers, error_logs.count, error_logs.last&.created_at)
	end

	# 发送浏览器被占用告警消息
	def self.send_browser_occupied_alert(browsers, error_count, last_error_time)
		require 'net/http'
		require 'json'

		webhook_url = ENV['DINGDING_WEBHOOK_URL']
		Rails.logger.info "webhook_url: #{webhook_url}"
		return unless webhook_url.present?

		browser_list = browsers.map { |name| "• #{name}" }.join("\n")

		message = "【养号】检测到多个指纹浏览器被占用\n\n"
		message += "📊 统计信息：\n"
		message += "• 最近2小时内错误次数：#{error_count} 次\n"
		message += "• 被占用的浏览器数量：#{browsers.size} 个\n\n"
		message += "🔐 被占用的指纹浏览器：\n#{browser_list}\n\n"
		message += "⏰ 检测时间：#{Time.current.strftime("%Y-%m-%d %H:%M:%S")}\n"
		message += "⏰ 最近错误时间：#{last_error_time&.strftime("%Y-%m-%d %H:%M:%S") || "无"}"
		Rails.logger.info message

		postbody = {"msgtype": "text","text": {"content": message}}
		headers = {
			"Content-Type": "application/json;charset=utf-8"
		}
		res = RestClient.post(webhook_url,postbody.to_json,headers = headers)
	end

	# 检查超时任务（超过8分钟未完成）并自动重置
	def self.check_timeout_tasks
		eight_minutes_ago = 8.minutes.ago

		timeout_operation_tasks = OperationTask.where(status: :executing)
		                                       .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		timeout_grok_tasks = GrokTask.where(status: :executing)
		                             .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		timeout_move_tasks = MoveTask.where(status: :executing)
		                             .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		timeout_heygen_tasks = HeygenTask.where(status: :executing)
		                                 .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		timeout_jianying_tasks = JianyingTask.where(status: :executing)
		                                     .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		timeout_huasheng_tasks = HuashengTask.where(status: :executing)
		                                     .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		timeout_notebooklm_tasks = NotebooklmTask.where(status: :executing)
		                                     .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)

		return if timeout_count == 0

		Rails.logger.warn "[TaskScheduler] 检测到 #{timeout_count} 个超时任务，正在重置..."

		# 重置运营任务
		timeout_operation_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end

		# 重置 Grok 任务
		timeout_grok_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end

		# 重置搬运任务
		timeout_move_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end

		# 重置 Heygen 任务
		timeout_heygen_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end

		# 重置剪映任务
		timeout_jianying_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end
		# 重置花生任务
		timeout_huasheng_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end
		# 重置 Notebooklm 任务
		timeout_notebooklm_tasks.each do |task|
			task.update!(
				status: :pending,
				account_id: nil,
				browser_id: nil,
				error_msg: "任务执行超时（超过8分钟）",
				start_at: nil
			)
		end

		send_timeout_alert(timeout_count, timeout_operation_tasks.count, timeout_grok_tasks.count, timeout_move_tasks.count, timeout_heygen_tasks.count, timeout_jianying_tasks.count, timeout_huasheng_tasks.count, timeout_notebooklm_tasks.count)
	end

	# 发送超时任务告警消息
	def self.send_timeout_alert(total_count, operation_count, grok_count, move_count, heygen_count = 0, jianying_count = 0, huasheng_count = 0, notebooklm_count = 0)
		require 'net/http'
		require 'json'

		webhook_url = ENV['DINGDING_WEBHOOK_URL']
		return unless webhook_url.present?

		message = "【养号】检测到超时任务\n\n"
		message += "📊 统计信息：\n"
		message += "• 总超时任务数：#{total_count} 个\n"
		message += "• 运营任务：#{operation_count} 个\n"
		message += "• Grok任务：#{grok_count} 个\n"
		message += "• 搬运任务：#{move_count} 个\n"
		message += "• Heygen任务：#{heygen_count} 个\n"
		message += "• 剪映任务：#{jianying_count} 个\n"
		message += "• 花生任务：#{huasheng_count} 个\n"
		message += "• Notebooklm任务：#{notebooklm_count} 个\n\n"
		message += "⏰ 超时阈值：8分钟\n"
		message += "⏰ 检测时间：#{Time.current.strftime("%Y-%m-%d %H:%M:%S")}"

		postbody = {"msgtype": "text","text": {"content": message}}
		headers = {
			"Content-Type": "application/json;charset=utf-8"
		}
		res = RestClient.post(webhook_url,postbody.to_json,headers = headers)
	end
end