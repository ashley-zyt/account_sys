class Admin::DashboardController < Admin::BaseController
	def index
		@accounts_total = Account.count
		@accounts_active = Account.active.count
		@accounts_unlogged = Account.where(status: 1).count
		@accounts_banned = Account.where(status: 2).count
		
		today_logs = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).includes(:move_task, :jianying_task)
		@accounts_active_today = today_logs.map { |log| log.task&.account_id }.compact.uniq.count

		@platform_stats = Account.group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
			hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
			hash[platform][:total] += count
			case status
			when "正常" then hash[platform][:active] += count
			when "未登录" then hash[platform][:unlogged] += count
			when "封禁/停用" then hash[platform][:banned] += count
			end
		end

		# 各工作模式账号统计卡片（由注册表驱动，新增模式自动出现）
		@work_type_cards = WorkMode.resource_modes.map do |mode|
			stats = Account.where(work_type: mode.name).group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
				hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
				hash[platform][:total] += count
				case status
				when "正常" then hash[platform][:active] += count
				when "未登录" then hash[platform][:unlogged] += count
				when "封禁/停用" then hash[platform][:banned] += count
				end
			end
			{
				mode: mode,
				stats: stats,
				total: Account.where(work_type: mode.name).count,
				active: Account.where(work_type: mode.name).active.count
			}
		end

		@browsers_total = Browser.count
		@browsers_normal = Browser.where(status: 0).count
		@browsers_network_error = Browser.where(status: 1).count
		@browsers_invalid = Browser.where(status: 2).count

		@today_logs_count = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).count
		@today_errors_count = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).failed.count

		@total_logs_count = TaskLog.count
		@total_errors_count = TaskLog.failed.count

		# 今日核心 KPI
		@today_success_count = @today_logs_count - @today_errors_count
		@today_success_rate = @today_logs_count > 0 ? ((@today_success_count.to_f / @today_logs_count) * 100).round(1) : 0
		@pending_publish_count = WorkMode.publishable_modes.sum { |m| m.task_model_class.where(status: :waiting_publish).count }

		@abnormal_accounts = fetch_abnormal_accounts(3)

		# 低库存预警：仅展示可用天数 < 10 天（含无库存/无法估算）的工作模式×主题×平台组合
		@low_stock_alerts = fetch_low_stock_alerts
	end

	# 预警阈值：可用天数 < 此值才会在仪表盘展示
	LOW_STOCK_DAY_THRESHOLD = 10

	# 低库存预警：按工作模式 → 主题 → 平台 三级聚合，仅保留需要预警的项
	# 计算基准：每个正常状态的账号每天固定发布 1 条（理论消耗速率，不看历史实际发布）
	#   日均消耗 = 正常账号数
	#   可用天数 = 剩余资源 / 正常账号数
	# 预警条件（满足任一即展示）：
	#   - 剩余资源 = 0（无库存，需补货）
	#   - 可用天数 < 阈值
	# 注：无正常账号的组合直接跳过（没有账号则不需要计算资源消耗）
	# @return [Array<Hash>] 工作模式维度聚合的预警列表
	def fetch_low_stock_alerts
		WorkMode.low_stock_track_modes.map do |mode|
			task_model = mode.task_model_class
			work_type = mode.name

			# 按 theme + platform 双维度统计 pending 数
			pending_counts = task_model.where(status: :pending).group(:theme, :platform).count

			# 该工作模式下 (theme, platform) → 正常状态账号数 的映射
			account_counts = Account.active
			                        .where(work_type: work_type)
			                        .group(:theme, :platform)
			                        .count

			# 仅遍历有正常账号的组合（无账号的组合无意义，直接跳过）
			platform_rows = account_counts.map do |(theme, platform), active_accounts|
				pending = pending_counts[[theme, platform]].to_i

				# 日均消耗 = 正常账号数（每个账号每天固定发1条）
				available_days = (pending.to_f / active_accounts).round(1)

				# 不需要预警：有库存且可用天数充足
				next nil if pending > 0 && available_days >= LOW_STOCK_DAY_THRESHOLD

				{
					theme: theme,
					platform: platform_label(platform),
					pending: pending,
					active_accounts: active_accounts,
					available_days: available_days
				}
			end.compact

			# 按 theme 分组，按可用天数升序（紧急的在前）
			grouped_by_theme = platform_rows.group_by { |row| row[:theme] }
			                                .map do |theme, rows|
				sorted_rows = rows.sort_by do |row|
					# 权重：无库存=0（最紧急），有可用天数=days 本身
					row[:pending] == 0 ? 0 : row[:available_days]
				end
				{ theme: theme, platforms: sorted_rows }
			end.sort_by do |group|
				group[:platforms].map { |row| row[:pending] == 0 ? 0 : row[:available_days] }.min
			end

			{
				work_type: work_type,
				themes: grouped_by_theme
			}
		end
	end

	private

	# group(:platform) 返回的是整数枚举值（1..5），这里映射回平台名用于展示
	def platform_label(platform)
		Account.platforms.key(platform) || platform.to_s
	end

	def fetch_abnormal_accounts(_min_consecutive_failures)
		error_counts = TaskLog.failed
			.joins(:log_account)
			.where("account_id IS NOT NULL")
			.where("run_at >= ?", 1.week.ago)
			.where(accounts: { status: "正常" })
			.group(:account_id)
			.order(Arel.sql("COUNT(*) DESC"))
			.limit(10)
			.count

		error_counts.map do |account_id, count|
			account = Account.find_by(id: account_id)
			next unless account

			last_error_log = TaskLog.failed
				.where(account_id: account_id)
				.order(run_at: :desc)
				.first

			{
				account: account,
				error_count: count,
				last_failure_time: last_error_log&.run_at,
				last_error: last_error_log&.error_msg
			}
		end.compact
	end
end
