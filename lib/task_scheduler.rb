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

					# 防同账号重复分配：该账号已有待发布/执行中的任务则跳过，避免同一账号堆多条 waiting_publish
					has_active_task = task_model.exists?(account_id: account.id, status: [:waiting_publish, :executing])
					next if has_active_task

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
		response = RemoteApiClient.get("https://#{machine_ip}/api/browser/locked", open_timeout: 100, read_timeout: 100)
		locked_data = JSON.parse(response.body)

		if locked_data.is_a?(Array)
			locked_data.map { |item| item['name'] || item[:name] }.compact
		elsif locked_data.is_a?(Hash) && locked_data['data'].is_a?(Array)
			locked_data['data'].map { |item| item['name'] || item[:name] }.compact
		else
			[]
		end
	end

	# 机器端返回的终态状态：只有这两个代表任务真正结束、可以补处理。
	# queued / running 表示任务还在机器端排队或执行中，绝不能当失败处理。
	MACHINE_TERMINAL_STATUSES = %w[success failed].freeze

	# 检查超时任务：优先基于「登记记录」主动查机器端真实状态，查不到才盲重置。
	# 异步化后，任务下发为 async（机器端排队+执行），排队等待 20 分钟属正常，故阈值放宽到 45 分钟。
	# 兜底两类边界：① 回调失败（Best Effort）→ 主动查机器端补结果；② 机器重启丢任务 → 查不到则重置。
	#
	# @param threshold [ActiveSupport::Duration] 判定超时的时间窗口，默认 45 分钟。
	#        机器端启动上报时传 0，表示「忽略时间窗口，立即检查全部登记记录」。
	# @param machine_ip [String, nil] 只处理这台机器上的登记记录；不传则处理全部机器。
	# @param include_untracked [Boolean] 是否额外兜底「无登记记录但卡在 executing」的任务。
	#        默认 true；机器端重启上报时传 false，否则会把其它机器正在执行的任务一并重置。
	def self.check_timeout_tasks(threshold: 45.minutes, machine_ip: nil, include_untracked: true)
		timeout_ago = threshold.ago

		# 1. 查超时仍未回调的登记记录，逐个查机器端真实状态
		scope = BrowserTaskRecord.pending
		scope = scope.where(machine_ip: machine_ip) if machine_ip.present?
		overdue = scope.where("created_at <= ?", timeout_ago).to_a
		overdue.each do |record|
			remote = fetch_remote_task(record.machine_ip, record.machine_task_id)
			if remote && MACHINE_TERMINAL_STATUSES.include?(remote['status'].to_s)
				# 机器端已有终态结果：补处理（等价于补一次回调）
				Rails.logger.info "[TaskScheduler] 超时任务 #{record.machine_task_id} 机器端状态=#{remote['status']}，补处理"
				BrowserTaskResultHandler.process(ref: record.ref, status: remote['status'], message: remote['message'], result: remote['result'])
				BrowserTaskRecord.mark_result!(record.machine_task_id, remote['status'], remote['message'])
			elsif remote
				# 机器端仍在排队/执行中：保持 pending，下一轮再查。
				# （排队不计入执行超时后，长排队会让任务超过 45 分钟仍未回调，属正常情况，
				#   不能拿 queued/running 去 process —— 那会被当成失败处理、误伤正在跑的任务。）
				Rails.logger.info "[TaskScheduler] 任务 #{record.machine_task_id} 仍在机器端执行中(status=#{remote['status']})，跳过"
			else
				# 机器端查不到（任务丢失/重启）：重置对应任务
				Rails.logger.warn "[TaskScheduler] 超时任务 #{record.machine_task_id} 机器端查不到，重置 #{record.ref}"
				reset_task_by_ref(record.ref)
				record.update!(status: BrowserTaskRecord::STATUS_UNKNOWN, message: '机器端任务丢失（超时未回调且查询不到）')
			end
		end

		# 2. 兜底：无登记记录但仍卡在 executing 的任务（老数据/记录丢失）也重置
		#    注意：这一段不带机器过滤条件，只有在常规定时兜底（阈值 45 分钟）时才执行；
		#    机器端重启上报走的是「按机器 + 忽略时间窗口」路径，必须跳过，否则会误伤其它机器。
		return unless include_untracked

		WorkMode.resource_modes.each do |mode|
			mode.task_model_class.where(status: :executing)
			                     .where("start_at IS NOT NULL AND start_at <= ?", timeout_ago)
			                     .each do |task|
				task.update!(
					status: :pending,
					account_id: nil,
					browser_id: nil,
					error_msg: "任务执行超时（超过45分钟未收到回调）",
					start_at: nil
				)
			end
		end
	end

	# 查机器端单个任务真实状态
	def self.fetch_remote_task(machine_ip, machine_task_id)
		return nil if machine_ip.blank? || machine_task_id.blank?
		response = RemoteApiClient.get("https://#{machine_ip}/tasks/#{machine_task_id}", open_timeout: 10, read_timeout: 20)
		return nil unless response.code.to_i == 200
		JSON.parse(response.body)
	rescue => e
		Rails.logger.error "[TaskScheduler] 查询机器端任务状态异常 #{machine_task_id}: #{e.message}"
		nil
	end

	# 按 ref 重置对应任务（机器端任务丢失时兜底）
	def self.reset_task_by_ref(ref)
		model_name, id = ref.to_s.split(':', 2)
		id = id.to_i

		if model_name == 'WarmupTask'
			# 养号任务：执行中超时且机器端丢失 → 标记失败（养号无重新分配语义）
			WarmupTask.where(id: id, status: :executing)
			          .update_all(status: :failed, error_msg: '机器端任务丢失（超时未回调且查询不到）', executed_at: Time.current)
		else
			task_model = model_name.safe_constantize
			return unless task_model.is_a?(Class) && task_model < ApplicationRecord && WorkMode.for_model(task_model)
			# 发文任务：重置回 pending（清账号/浏览器），等重新分配
			task_model.where(id: id, status: :executing)
			          .update_all(status: :pending, account_id: nil, browser_id: nil, start_at: nil,
			                      error_msg: '机器端任务丢失（超时未回调且查询不到）')
		end
	end
end