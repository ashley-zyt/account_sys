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

	def self.assign_operation_resources
		today = Date.today
		today_start = today.beginning_of_day
		today_end = today.end_of_day

		Account.active.where(work_type: "人工运营").each do |account|
			has_posted_today = OperationTask.exists?(
				account_id: account.id,
				status: :success,
				actual_publish_time: today_start..today_end
			)

			next if has_posted_today

			pending_task = OperationTask.where(status: :pending, platform: account.platform, theme: account.theme).order(created_at: :asc).first

			if pending_task
				ActiveRecord::Base.transaction do
					pending_task.update!(
						account_id: account.id,
						browser_id: account.browser_id,
						status: :waiting_publish
					)
				end
				Rails.logger.info "人工运营账号 #{account.account_name}[#{account.platform}-#{account.theme}] 分配运营资源成功"
			else
				Rails.logger.warn "人工运营账号 #{account.account_name}[#{account.platform}-#{account.theme}] 暂无可用运营资源"
			end
		end
		TaskScheduler.find_locked_browsers_in_pending_tasks
	end

	# 找出待执行任务中与锁定接口重合的指纹浏览器名称
	def self.find_locked_browsers_in_pending_tasks

		# 1. 获取待执行任务中的指纹浏览器名称
		pending_browser_ids = []

		# 从搬运任务中获取
		# pending_browser_ids += MoveTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从运营任务中获取
		pending_browser_ids += OperationTask.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 获取浏览器名称
		pending_browser_names = Browser.where(id: pending_browser_ids.uniq).pluck(:profile_name).uniq

		return { pending_browsers: pending_browser_names, locked_browsers: [], matched_browsers: [] } if pending_browser_names.empty?

		# 2. 调用锁定接口获取锁定的浏览器列表
		begin
			uri = URI('http://174.139.46.117:8080/api/browser/locked')
			http = Net::HTTP.new(uri.host, uri.port)
			http.open_timeout = 10
			http.read_timeout = 10

			response = http.get(uri.path)
			locked_data = JSON.parse(response.body)

			# 提取锁定的浏览器名称
			locked_browser_names = if locked_data.is_a?(Array)
				locked_data.map { |item| item['name'] || item[:name] }.compact
			elsif locked_data.is_a?(Hash) && locked_data['data'].is_a?(Array)
				locked_data['data'].map { |item| item['name'] || item[:name] }.compact
			else
				[]
			end

			# 3. 找出重合的浏览器名称
			matched_browser_names = pending_browser_names & locked_browser_names

			# 4. 如果有匹配的浏览器，发送钉钉通知
			if matched_browser_names.present?
				send_locked_browsers_alert(matched_browser_names, pending_browser_names, locked_browser_names)
			end

			{
				pending_browsers: pending_browser_names,
				locked_browsers: locked_browser_names,
				matched_browsers: matched_browser_names
			}
		rescue => e
			Rails.logger.error "调用锁定浏览器接口失败: #{e.message}"
			{
				pending_browsers: pending_browser_names,
				locked_browsers: [],
				matched_browsers: [],
				error: e.message
			}
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

		message = "【养号】检测到被锁定的浏览器正在执行任务\n\n"
		message += "🔒 被锁定的浏览器（共 #{matched_browsers.size} 个）：\n#{matched_list}\n\n"
		message += "📋 待执行任务中的浏览器（共 #{pending_browsers.size} 个）：\n#{pending_list}\n\n"
		message += "🔐 锁定接口返回的浏览器（共 #{locked_browsers.size} 个）：\n#{locked_list}\n\n"
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
		return unless webhook_url.present?

		browser_list = browsers.map { |name| "• #{name}" }.join("\n")

		message = "【警告】检测到多个指纹浏览器被占用\n\n"
		message += "📊 统计信息：\n"
		message += "• 最近2小时内错误次数：#{error_count} 次\n"
		message += "• 被占用的浏览器数量：#{browsers.size} 个\n\n"
		message += "🔐 被占用的指纹浏览器：\n#{browser_list}\n\n"
		message += "⏰ 检测时间：#{Time.current.strftime("%Y-%m-%d %H:%M:%S")}\n"
		message += "⏰ 最近错误时间：#{last_error_time&.strftime("%Y-%m-%d %H:%M:%S") || "无"}"

		postbody = { msgtype: "text", text: { content: message } }
		headers = { "Content-Type" => "application/json;charset=utf-8" }
		RestClient.post(webhook_url, postbody.to_json, headers)
	end
end