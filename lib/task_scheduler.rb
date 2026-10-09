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

	# @param platform [String, nil] 限定平台
	# @param only_combos [Array<Array>, nil] 只处理指定的 [platform, theme] 组合
	#        （用于「重跑被中断任务」时精准补发，避免顺带把同平台其它正常账号提前发掉）；
	#        为 nil 时处理全部 —— 保持原有行为，既有调用点不受影响。
	# @param redirect_logger [Boolean] 是否把 Rails.logger 重定向到独立日志文件。
	#        默认 true（定时任务用，便于单独排查）；从 web 请求的后台线程调用时传 false，
	#        否则会把整个进程的日志都写到这个文件里，造成日志错乱。
	def self.assign_resources(platform: nil, only_combos: nil, redirect_logger: true)
		if redirect_logger
			logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'taskscheduler_assignresources.log'))
			logger.formatter = Rails.logger.formatter
			Rails.logger = logger
		end

		today = Date.today
		today_start = today.beginning_of_day
		today_end = today.end_of_day

		WorkMode.scheduler_assign_modes.each do |mode|
			begin
				task_model = mode.task_model_class
				type_name = mode.name
				accounts = Account.active.where(work_type: mode.name)
				accounts = accounts.where(platform: platform) if platform.present?
				# 只补发指定 [platform, theme] 组合的账号（重跑被中断任务时用）
				accounts = accounts.select { |a| only_combos.include?([a.platform, a.theme]) } if only_combos.present?

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
					# 按账号自身平台判断（而非传入的 platform 参数），保证全平台补发轮也能正确冷却
					if account.platform == 'tiktok' && account.zero_views_in_past_3_days?
						Rails.logger.info "TikTok账号 #{account.account_name}[#{account.platform}-#{account.theme}] 过去3天发文浏览量均为0，暂停3天后再分配资源"
						next
					end

					# 分配 [platform, theme] 匹配的 pending 任务，不限制创建时间：
					# 历史遗留的 pending 也参与分配。
					# 排序：failure_count 升序（0=全新未失败优先），再按创建时间最旧优先（FIFO）。
					# 这样「资源有问题」失败过的坏资源（failure_count>0）排到队尾、不挡好资源，
					# 账号在后续补发轮能直接拿到全新资源发成，坏资源最终被 3 次失败规则淘汰。
					pending_task = task_model
						.where(status: :pending, platform: account.platform, theme: account.theme)
						.order(:failure_count, created_at: :asc).first

					if pending_task
						ActiveRecord::Base.transaction do
							pending_task.update!(
								account_id: account.id,
								browser_id: account.browser_id,
								status: :waiting_publish
							)
							# 发活那一刻固化归属（释放时只标记、不删除，供迟到的回调归档日志）
							TaskAssignment.record!(pending_task)
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

	# 补发循环：平台发布窗口后触发一次，持续补发直到「资源耗尽 / 账号全部发成」。
	# 每轮 = 分配资源 + 发布 + 等待上一轮 executing 任务收敛，避免时序重叠。
	# 终止条件：该平台已无「今天未发成且还有可用 pending 资源」的账号（资源耗尽或全部发成）。
	# max_rounds 是纯安全上限（防止异常分类导致死循环），正常会在资源耗尽前自然结束。
	# 配合 has_posted_today / has_active_task 闸门 + 坏资源降优先级（failure_count 排序）
	# + 资源有问题累计 3 次 → failed，实现「账号当天持续换资源直到发成或资源耗尽」。
	def self.retry_loop(platform:, max_rounds: 6, settle_timeout: 30.minutes, settle_poll: 1.minute)
		# 先等首轮（平台发布窗口）任务执行结束，再开始补发——「查询执行结束，结束直接开始」
		wait_until_settled(platform, settle_timeout, settle_poll)

		# 首轮全部成功（无失败回 pending）→ 无需补发，直接结束
		unless unposted_accounts_with_pending?(platform)
			Rails.logger.info "[TaskScheduler] 平台 #{platform} 首轮全部成功，无需补发"
			return
		end

		rounds = 0
		loop do
			rounds += 1
			Rails.logger.info "[TaskScheduler] 平台 #{platform} 补发第 #{rounds} 轮开始"
			assign_resources(platform: platform)
			PublishScheduler.run(platform: platform)

			wait_until_settled(platform, settle_timeout, settle_poll)

			unless unposted_accounts_with_pending?(platform)
				Rails.logger.info "[TaskScheduler] 平台 #{platform} 已无「未发成且有可用资源」的账号，补发结束（共 #{rounds} 轮）"
				break
			end

			if rounds >= max_rounds
				Rails.logger.warn "[TaskScheduler] 平台 #{platform} 补发达到安全上限 #{max_rounds} 轮，强制结束"
				break
			end
		end
	end

	# 平台下是否还有「今天未发成 + 存在可分配 pending 资源」的账号（决定补发循环是否继续）。
	def self.unposted_accounts_with_pending?(platform)
		today = Date.today.all_day

		WorkMode.scheduler_assign_modes.any? do |mode|
			task_model = mode.task_model_class

			# 该工作模式下、该平台内还有 pending 资源的主题集合
			pending_themes = task_model.where(status: :pending, platform: platform).distinct.pluck(:theme)
			next false if pending_themes.empty?

			# 这些主题里，今天已经发成功的账号（这些账号无需再补发）
			posted_ids = task_model.where(status: :success, actual_publish_time: today, platform: platform)
			                       .distinct.pluck(:account_id).compact

			# 还有「正常、今天没发成」的账号 → 仍有补发空间
			accounts = Account.active.where(work_type: mode.name, platform: platform, theme: pending_themes)
			accounts = accounts.where.not(id: posted_ids) if posted_ids.any?
			accounts.exists?
		end
	end

	# 等待某平台所有 executing 任务收敛（本轮发布结果都已回调回来）。
	# 若连续一轮计数不再下降，说明剩余的是卡死任务（丢失回调），不再死等、交给 check_timeout_tasks 兜底回收。
	def self.wait_until_settled(platform, timeout, poll, stuck_after: 5.minutes)
		deadline = Time.current + timeout
		last_decrease = Time.current
		prev = nil
		loop do
			executing = WorkMode.scheduler_assign_modes.sum do |mode|
				mode.task_model_class.where(status: :executing, platform: platform).count
			end
			return if executing.zero?

			# 计数下降则刷新「最后进展时间」
			last_decrease = Time.current if prev && executing < prev

			# 连续 stuck_after（默认 5 分钟）无进展 → 剩余是卡死任务，停止等待、交给超时兜底
			if Time.current - last_decrease >= stuck_after
				Rails.logger.warn "[TaskScheduler] 平台 #{platform} 仍有 #{executing} 个 executing 任务且 #{stuck_after.inspect} 无进展（疑似卡死），停止等待、交给超时兜底"
				break
			end

			break if Time.current >= deadline
			prev = executing
			sleep(poll)
		end
	end

	# 任务被兜底重置时写入 error_msg 的关键词 —— 用于识别「被中断」的任务。
	#   ① 机器端进程重启/任务丢失 → reset_task_by_ref
	#   ② 长时间无回调超时        → check_timeout_tasks 第二段兜底
	INTERRUPTED_ERROR_KEYWORDS = ['机器端任务丢失', '任务执行超时'].freeze

	# 找出「被中断后已被重置回 pending」的发布类任务（各平台资源队列）。
	#
	# 说明：重置时 account_id / browser_id 会被清空，所以无法直接知道它原本属于哪个账号，
	# 但任务自身的 platform / theme 仍在 —— 这正是重新分配所需的匹配键。
	#
	# @param platform [String, nil] 限定平台
	# @return [Array] 任务实例数组（跨模型合并）
	def self.interrupted_pending_tasks(platform: nil)
		conds  = INTERRUPTED_ERROR_KEYWORDS.map { 'error_msg LIKE ?' }.join(' OR ')
		values = INTERRUPTED_ERROR_KEYWORDS.map { |k| "%#{k}%" }

		WorkMode.scheduler_assign_modes.flat_map do |mode|
			scope = mode.task_model_class.where(status: :pending).where(conds, *values)
			scope = scope.where(platform: platform) if platform.present?
			scope.to_a
		end
	end

	# 主动重跑「被中断」的发布任务：立即重新分配资源并下发，不等平台固定分配窗口。
	#
	# 场景：机器端进程重启/崩溃后，被兜底重置回 pending 的任务要等该平台下一个固定分配窗口
	# （如 IG 早上崩掉、得等到第二天 7:50）才会重跑，表现为「重启后任务长时间没动静」。
	# 本方法供后台「异步任务」页的「重跑丢失任务」按钮调用，点了就立刻补一次。
	#
	# 设计与安全：
	#   - 只针对「确实有被中断任务」的 [platform, theme] 组合补发（仅这些账号会被分配），
	#     不会顺带把同平台其它正常账号的发布提前；
	#   - 防重复发布的两道闸门依然生效：assign_resources 的 has_posted_today / has_active_task，
	#     以及 PublishScheduler.attempt_task 的「该账号今天已发布成功则重置跳过」；
	#   - 养号任务不在范围内（中断后标记为 failed，无重新分配语义，由每日养号调度负责）。
	#
	# @param platform [String, nil] 限定平台
	# @return [Hash] { interrupted_count:, details:, errors: }
	def self.retry_interrupted_tasks(platform: nil)
		interrupted = interrupted_pending_tasks(platform: platform)
		return { interrupted_count: 0, details: [], errors: [] } if interrupted.empty?

		details = []
		errors  = []

		interrupted.group_by(&:platform).each do |pf, tasks|
			combos = tasks.map { |t| [t.platform, t.theme] }.uniq
			begin
				Rails.logger.info "[TaskScheduler] 重跑被中断任务：平台 #{pf}，组合 #{combos.inspect}，共 #{tasks.size} 条（#{tasks.map { |t| "#{t.class.name}:#{t.id}" }.join(', ')}）"

				# 1. 只给「有被中断任务」的账号补发资源
				#    redirect_logger: false —— 这里是 web 请求的后台线程，不能全局替换 Rails.logger
				assign_resources(platform: pf, only_combos: combos, redirect_logger: false)

				# 2. 只下发刚补发的这批任务。
				#    不用 PublishScheduler.run —— 它内部会再跑一次「不带过滤的 assign_resources」，
				#    那会把该平台其它正常账号的资源也一并分配并下发（等于提前触发整个平台的发布）。
				tasks_to_publish = PublishScheduler.fetch_all_tasks(platform: pf)
				                              .select { |t| combos.include?([t.platform, t.theme]) }

				if tasks_to_publish.empty?
					Rails.logger.info "[TaskScheduler] 平台 #{pf} 本轮无任务可下发（对应账号今天已发布成功，或已有进行中/待发布任务）"
				else
					PublishScheduler.run_tasks_with_pool(tasks_to_publish)
				end

				details << "#{pf}(识别#{tasks.size}/下发#{tasks_to_publish.size})"
			rescue => e
				Rails.logger.error "[TaskScheduler] 重跑平台 #{pf} 的被中断任务异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
				errors << "#{pf}: #{e.message}"
			end
		end

		Rails.logger.info "[TaskScheduler] 重跑被中断任务完成：#{details.join(' / ')}#{errors.any? ? "，失败：#{errors.join('; ')}" : ''}"
		{ interrupted_count: interrupted.size, details: details, errors: errors }
	end

	# 重新启动失败的任务（后台「异步任务」页批量选择失败记录后触发）
	# 按 ref 前缀分派：
	#   - 发文任务（资源队列模型）→ 重新分配资源并下发发布
	#   - 养号（WarmupTask）→ 重新下发养号
	#   - 采集（Account）→ 重新下发采集指令
	#   - 私信/查回复（kol_message / kol_contact）→ 跳过（有 KolScheduler 自动重试）
	# @param record_ids [Array<Integer>] 选中的 BrowserTaskRecord id
	# @return [Hash] { publish:, nurture:, fetch:, skipped: }
	def self.retry_failed_records(record_ids)
		records = BrowserTaskRecord.where(id: record_ids, status: BrowserTaskRecord::STATUS_FAILED).to_a
		return { publish: 0, nurture: 0, fetch: 0, skipped: 0 } if records.empty?

		publish_refs = []
		nurture_refs = []
		fetch_refs   = []
		skipped      = 0

		records.each do |r|
			model_name = r.ref.to_s.split(':', 2).first
			case model_name
			when 'WarmupTask' then nurture_refs << r.ref
			when 'Account'    then fetch_refs << r.ref
			when 'kol_message', 'kol_contact' then skipped += 1
			else publish_refs << r.ref
			end
		end

		publish_count = retry_publish_by_refs(publish_refs)
		nurture_count = retry_nurture_by_refs(nurture_refs)
		fetch_count   = retry_fetch_by_refs(fetch_refs)

		Rails.logger.info "[TaskScheduler] 重新启动失败任务完成：发文=#{publish_count} 养号=#{nurture_count} 采集=#{fetch_count} 跳过=#{skipped}"
		{ publish: publish_count, nurture: nurture_count, fetch: fetch_count, skipped: skipped }
	end

	# 重新发布失败的发文任务：按 ref 定位任务，再按平台+主题组合重新分配 + 下发
	def self.retry_publish_by_refs(refs)
		return 0 if refs.empty?

		tasks = []
		refs.each do |ref|
			model_name, id = ref.split(':', 2)
			task_model = model_name.safe_constantize
			next unless task_model.is_a?(Class) && task_model < ApplicationRecord && WorkMode.for_model(task_model)
			t = task_model.find_by(id: id.to_i)
			tasks << t if t
		end
		return 0 if tasks.empty?

		details = []
		tasks.group_by(&:platform).each do |pf, ts|
			combos = ts.map { |t| [t.platform, t.theme] }.uniq
			begin
				Rails.logger.info "[TaskScheduler] 重新启动失败发文任务：平台 #{pf}，组合 #{combos.inspect}，共 #{ts.size} 条"
				assign_resources(platform: pf, only_combos: combos, redirect_logger: false)
				to_publish = PublishScheduler.fetch_all_tasks(platform: pf)
				                              .select { |t| combos.include?([t.platform, t.theme]) }
				if to_publish.empty?
					Rails.logger.info "[TaskScheduler] 平台 #{pf} 无任务可下发（账号今天已发布成功或已有进行中任务）"
				else
					PublishScheduler.run_tasks_with_pool(to_publish)
				end
				details << "#{pf}(#{to_publish.size})"
			rescue => e
				Rails.logger.error "[TaskScheduler] 重新启动平台 #{pf} 失败任务异常: #{e.message}"
			end
		end

		Rails.logger.info "[TaskScheduler] 重新启动失败发文任务完成：#{details.join(' / ')}"
		tasks.size
	end

	# 重新下发失败的养号任务
	def self.retry_nurture_by_refs(refs)
		return 0 if refs.empty?

		count = 0
		refs.each do |ref|
			_, id = ref.split(':', 2)
			warmup_task = WarmupTask.find_by(id: id.to_i)
			next unless warmup_task && warmup_task.account && warmup_task.account.browser&.machine_ip.present?

			begin
				result = WarmupScheduler.execute_warmup_for_account(warmup_task.account, warmup_task.account.browser.machine_ip)
				count += 1 if result == :executed
			rescue => e
				Rails.logger.error "[TaskScheduler] 重新启动养号 #{ref} 异常: #{e.message}"
			end
		end
		count
	end

	# 重新下发失败的采集任务
	def self.retry_fetch_by_refs(refs)
		return 0 if refs.empty?

		count = 0
		refs.each do |ref|
			_, id = ref.split(':', 2)
			account = Account.find_by(id: id.to_i)
			next unless account && account.browser&.machine_ip.present?

			begin
				result = Util.fetch_account_post_data(account_id: account.id)
				count += 1 if result[:success]
			rescue => e
				Rails.logger.error "[TaskScheduler] 重新启动采集 #{ref} 异常: #{e.message}"
			end
		end
		count
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

	# 机器端返回的「正常终态」：可以补处理（等价于补一次回调）。
	MACHINE_TERMINAL_STATUSES = %w[success failed].freeze
	# 机器端「仍在进行中」的状态：保持 pending，下一轮再查，绝不能当失败/中断处理。
	MACHINE_RUNNING_STATUSES = %w[queued running].freeze
	# 机器端「重启中断」状态：服务重启时快照里未完成的任务会被标记为此状态。
	# 机器端任务记录已持久化（重启后仍可查到，状态=interrupted），不再返回 404，
	# 所以 interrupted 与「查不到(nil)」一样，都需要重置对应任务。
	MACHINE_INTERRUPTED_STATUS = 'interrupted'.freeze
	# 机器端「因 Undetectable 未启动而暂停」状态：任务未回调、本机挂起等待人工确认启动。
	# 兜底扫描遇到它必须保持 pending 跳过，绝不能当「丢失」重置——否则会重复下发，
	# 与「等人工确认后再恢复执行」的语义冲突。
	MACHINE_PAUSED_STATUS = 'paused'.freeze

	# 检查超时任务：优先基于「登记记录」主动查机器端真实状态，查不到才盲重置。
	# 异步化后，任务下发为 async（机器端排队+执行），排队等待 20 分钟属正常，故阈值放宽到 45 分钟。
	# 兜底两类边界：① 回调失败（Best Effort）→ 主动查机器端补结果；② 机器重启丢任务 → 查不到则重置。
	#
	# @param threshold [ActiveSupport::Duration, Integer] 判定超时的时间窗口，默认 45 分钟。
	#        传 0（机器端启动上报）表示「忽略时间窗口，立即检查全部登记记录」。
	# @param machine_ip [String, nil] 只处理这台机器上的登记记录；不传则处理全部机器。
	# @param include_untracked [Boolean] 是否额外兜底「无登记记录但卡在 executing」的任务。
	#        默认 true；机器端重启上报时传 false，否则会把其它机器正在执行的任务一并重置。
	def self.check_timeout_tasks(threshold: 45.minutes, machine_ip: nil, include_untracked: true)
		# threshold 为 0 表示「忽略时间窗口，立即检查全部」；此时 timeout_ago 置 nil，
		# 下面的 overdue 查询就不再按 created_at 过滤，直接取全部登记记录。
		timeout_ago = threshold.to_i.zero? ? nil : Time.now - threshold

		# 1. 查超时仍未回调的登记记录，逐个查机器端真实状态
		scope = BrowserTaskRecord.pending
		scope = scope.where(machine_ip: machine_ip) if machine_ip.present?
		overdue = timeout_ago ? scope.where("created_at <= ?", timeout_ago).to_a : scope.to_a

		# 第 1 段里「判定为仍在机器端排队/执行、或因 Undetectable 未启动而暂停」的 ref。
		# 这些任务是有意在等（尤其 paused：等人工启动或等 MachinePauseMonitor 自动恢复），
		# 第 2 段必须跳过，否则会一边跳过、一边盲重置，还会引发重复下发。
		kept_refs = []

		overdue.each do |record|
			remote = fetch_remote_task(record.machine_ip, record.machine_task_id)
			status = remote ? remote['status'].to_s : nil

			if status && MACHINE_TERMINAL_STATUSES.include?(status)
				# 机器端已有正常终态：补处理（等价于补一次回调）
				Rails.logger.info "[TaskScheduler] 超时任务 #{record.machine_task_id} 机器端状态=#{status}，补处理"
				BrowserTaskResultHandler.process(ref: record.ref, status: status, message: remote['message'], result: remote['result'])
				BrowserTaskRecord.mark_result!(record.machine_task_id, status, remote['message'])
			elsif status && (MACHINE_RUNNING_STATUSES.include?(status) || status == MACHINE_PAUSED_STATUS)
				# 机器端仍在排队/执行中，或因 Undetectable 未启动而暂停（等人工确认启动）：
				# 保持 pending，下一轮再查，绝不重置/重复下发（并把 ref 记下来供第 2 段跳过）。
				kept_refs << record.ref.to_s if record.ref.present?
				Rails.logger.info "[TaskScheduler] 任务 #{record.machine_task_id} 仍在机器端执行中(status=#{status})，跳过"
			else
				# 查不到（超期/clear）或 interrupted（服务重启中断）：都重置对应任务
				interrupted = status == MACHINE_INTERRUPTED_STATUS
				reason = interrupted ? '机器端任务被服务重启中断' : '机器端任务丢失（超时未回调且查询不到）'
				Rails.logger.warn "[TaskScheduler] 任务 #{record.machine_task_id} #{interrupted ? '状态=interrupted（重启中断）' : '机器端查不到'}，重置 #{record.ref}"
				reset_task_by_ref(record.ref)
				record.update!(status: BrowserTaskRecord::STATUS_UNKNOWN, message: reason)
			end
		end

		# 2. 兜底：无登记记录但仍卡在 executing 的任务（老数据/记录丢失）也重置
		#    注意：这一段不带机器过滤条件，只有在常规定时兜底（阈值 45 分钟）时才执行；
		#    机器端重启上报走的是「按机器 + 忽略时间窗口」路径，必须跳过，否则会误伤其它机器。
		return unless include_untracked
		return if timeout_ago.nil?

		WorkMode.resource_modes.each do |mode|
			mode.task_model_class.where(status: :executing)
			                     .where("start_at IS NOT NULL AND start_at <= ?", timeout_ago)
			                     .each do |task|
				# 第 1 段已确认「机器端仍在排队/执行中或因 Undetectable 未启动暂停」的任务：
				# 跳过，交给机器端继续跑 / 等 MachinePauseMonitor 自动恢复，不在这里当超时重置。
				if kept_refs.include?("#{task.class.name}:#{task.id}")
					Rails.logger.info "[TaskScheduler] 任务 #{task.class.name}##{task.id} 机器端仍在执行或已暂停，跳过超时重置"
					next
				end

				# 先把归属标为「已释放」（只标记、不删记录）：下面要清空任务上的 account_id/browser_id，
				# 而回调可能还在路上，届时要靠 TaskAssignment 认人。
				TaskAssignment.release!(task.task_uuid, '任务执行超时，重置待重新分配')
				task.update!(
					status: :pending,
					account_id: nil,
					browser_id: nil,
					error_msg: "任务执行超时（超过45分钟未收到回调）",
					start_at: nil
				)
			end
		end

		# 3. 硬上限：executing 超过 3 小时强制释放（机器端一直 running 卡死的情况）
		force_release_stuck_tasks
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
			scope = task_model.where(id: id, status: :executing)
			# 先把归属标为「已释放」（只标记、不删记录）：下面就要把任务上的 account_id/browser_id 清空，
			# 而这条任务的回调可能还在路上，届时要靠 TaskAssignment 认人，否则 task_logs 对不上账号/浏览器。
			TaskAssignment.release_many!(scope.pluck(:task_uuid), '机器端任务丢失，重置待重新分配')
			scope.update_all(status: :pending, account_id: nil, browser_id: nil, start_at: nil,
			                 error_msg: '机器端任务丢失（超时未回调且查询不到）')
		end
	end

	# 硬上限：任务卡在 executing 超过 hard_limit（默认 3 小时）的，无论机器端状态如何，强制释放回 pending。
	# 用于兜底「机器端一直返回 running/queued、状态卡死不动」的情况。
	def self.force_release_stuck_tasks(hard_limit: 3.hours)
		cutoff = Time.current - hard_limit
		total = 0

		WorkMode.resource_modes.each do |mode|
			mode.task_model_class.where(status: :executing)
			                     .where("start_at IS NOT NULL AND start_at <= ?", cutoff)
			                     .find_each do |task|
				# 关联的登记记录一并标「已丢失」，避免后续 check_timeout_tasks 再查机器端
				BrowserTaskRecord.where(ref: "#{task.class.name}:#{task.id}", status: BrowserTaskRecord::STATUS_PENDING)
				                 .update_all(status: BrowserTaskRecord::STATUS_UNKNOWN, message: '执行超时超过3小时，强制释放')

				TaskAssignment.release!(task.task_uuid, '执行超时超过3小时，强制释放')
				task.update_columns(
					status: task.class.statuses[:pending],
					account_id: nil,
					browser_id: nil,
					start_at: nil,
					error_msg: '执行超时超过3小时，强制释放待重新分配',
					updated_at: Time.current
				)
				total += 1
			end
		end

		Rails.logger.warn "[TaskScheduler] 硬上限强制释放 #{total} 条卡死任务" if total > 0
		total
	end
end