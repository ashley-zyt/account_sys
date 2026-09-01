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

		WorkMode.scheduler_assign_modes.each do |mode|
			begin
				task_model = mode.task_model_class
				type_name = mode.name
				accounts = Account.active.where(work_type: mode.name)
				accounts = accounts.where(platform: platform) if platform.present?

				accounts.each do |account|
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
				Rails.logger.error "[TaskScheduler] 处理 #{mode.name} 资源分配时发生异常: #{e.message}"
				Rails.logger.error "[TaskScheduler] 异常堆栈: #{e.backtrace.join("\n")}"
			end
		end

		TaskScheduler.find_locked_browsers_in_pending_tasks
	end

	# 找出待执行任务中与锁定接口重合的指纹浏览器名称
	# 遍历所有运营机器（browser.machine_ip）查询锁定状态，避免遗漏其他机器上的锁
	def self.find_locked_browsers_in_pending_tasks

		# 1. 获取待执行任务中的指纹浏览器（遍历注册表所有资源队列）
		pending_browser_ids = []

		WorkMode.resource_modes.each do |mode|
			pending_browser_ids += mode.task_model_class.where(status: :waiting_publish).where.not(browser_id: nil).pluck(:browser_id).uniq
		end

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
		response = RemoteApiClient.get("http://#{machine_ip}:8080/api/browser/locked", open_timeout: 100, read_timeout: 100)
		locked_data = JSON.parse(response.body)

		if locked_data.is_a?(Array)
			locked_data.map { |item| item['name'] || item[:name] }.compact
		elsif locked_data.is_a?(Hash) && locked_data['data'].is_a?(Array)
			locked_data['data'].map { |item| item['name'] || item[:name] }.compact
		else
			[]
		end
	end

	# 检查超时任务（超过8分钟未完成）并自动重置
	def self.check_timeout_tasks
		eight_minutes_ago = 8.minutes.ago

		WorkMode.resource_modes.each do |mode|
			mode.task_model_class.where(status: :executing)
			                     .where("start_at IS NOT NULL AND start_at <= ?", eight_minutes_ago)
			                     .each do |task|
				task.update!(
					status: :pending,
					account_id: nil,
					browser_id: nil,
					error_msg: "任务执行超时（超过8分钟）",
					start_at: nil
				)
			end
		end
	end
end