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

		@auto_account_stats = Account.where(work_type: 0).group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
			hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
			hash[platform][:total] += count
			case status
			when "正常" then hash[platform][:active] += count
			when "未登录" then hash[platform][:unlogged] += count
			when "封禁/停用" then hash[platform][:banned] += count
			end
		end
		@auto_account_total = Account.where(work_type: 0).count
		@auto_account_active = Account.where(work_type: 0).active.count

		@manual_account_stats = Account.where(work_type: 3).group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
			hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
			hash[platform][:total] += count
			case status
			when "正常" then hash[platform][:active] += count
			when "未登录" then hash[platform][:unlogged] += count
			when "封禁/停用" then hash[platform][:banned] += count
			end
		end
		@manual_account_total = Account.where(work_type: 3).count
		@manual_account_active = Account.where(work_type: 3).active.count

		@grok_account_stats = Account.where(work_type: 4).group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
			hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
			hash[platform][:total] += count
			case status
			when "正常" then hash[platform][:active] += count
			when "未登录" then hash[platform][:unlogged] += count
			when "封禁/停用" then hash[platform][:banned] += count
			end
		end
		@grok_account_total = Account.where(work_type: 4).count
		@grok_account_active = Account.where(work_type: 4).active.count

		@heygen_account_stats = Account.where(work_type: 5).group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
			hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
			hash[platform][:total] += count
			case status
			when "正常" then hash[platform][:active] += count
			when "未登录" then hash[platform][:unlogged] += count
			when "封禁/停用" then hash[platform][:banned] += count
			end
		end
		@heygen_account_total = Account.where(work_type: 5).count
		@heygen_account_active = Account.where(work_type: 5).active.count

		@browsers_total = Browser.count
		@browsers_normal = Browser.where(status: 0).count
		@browsers_network_error = Browser.where(status: 1).count
		@browsers_invalid = Browser.where(status: 2).count

		@today_logs_count = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).count
		@today_errors_count = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).failed.count

		@total_logs_count = TaskLog.count
		@total_errors_count = TaskLog.failed.count

		@abnormal_accounts = fetch_abnormal_accounts(3)

		# 低库存预警：仅展示可用天数 < 10 天（含无库存/无法估算）的工作模式×主题×平台组合
		@low_stock_alerts = fetch_low_stock_alerts
	end

	# 资源剩余可用天数统计配置（与 TaskScheduler.assign_resources 保持一致，排除 Heygen）
	RESOURCE_DAYS_CONFIGS = [
		{ work_type: "视频搬运", task_model: MoveTask },
		{ work_type: "人工运营", task_model: OperationTask },
		{ work_type: "Grok", task_model: GrokTask },
		{ work_type: "剪映", task_model: JianyingTask }
	].freeze

	# 预警阈值：可用天数 < 此值才会在仪表盘展示
	LOW_STOCK_DAY_THRESHOLD = 10

	# 低库存预警：按工作模式 → 主题 → 平台 三级聚合，仅保留需要预警的项
	# 预警条件（满足任一即展示）：
	#   - 剩余资源 = 0（无库存）
	#   - 近 7 天有成功发布但可用天数 < 阈值
	#   - 剩余资源 > 0 但近 7 天无成功发布（无法估算消耗速率，存在滞销风险）
	# @return [Array<Hash>] 工作模式维度聚合的预警列表
	def fetch_low_stock_alerts
		consumption_window_days = 7
		window_start = consumption_window_days.days.ago.beginning_of_day

		RESOURCE_DAYS_CONFIGS.map do |config|
			task_model = config[:task_model]

			# 按 theme + platform 双维度统计 pending 与近 7 天成功发布数
			pending_counts = task_model.where(status: :pending).group(:theme, :platform).count
			success_counts = task_model.where(status: :success)
			                           .where("actual_publish_time >= ?", window_start)
			                           .group(:theme, :platform)
			                           .count

			# 合并所有出现过的 (theme, platform) 组合
			keys = (pending_counts.keys + success_counts.keys).uniq

			platform_rows = keys.map do |theme, platform|
				pending = pending_counts[[theme, platform]].to_i
				success_in_window = success_counts[[theme, platform]].to_i
				daily_avg = success_in_window.to_f / consumption_window_days

				available_days = if daily_avg > 0
					(pending.to_f / daily_avg).round(1)
				else
					nil
				end

				# 预警过滤
				next nil if pending > 0 && available_days && available_days >= LOW_STOCK_DAY_THRESHOLD

				{
					theme: theme,
					platform: platform,
					pending: pending,
					daily_avg: daily_avg.round(2),
					available_days: available_days
				}
			end.compact

			# 按 theme 分组，再按可用天数升序（紧急的在前）
			grouped_by_theme = platform_rows.group_by { |row| row[:theme] }
			                                .map do |theme, rows|
				sorted_rows = rows.sort_by do |row|
					# 排序权重：无库存=0（最紧急），无法估算=1，有可用天数=2+days
					case
					when row[:pending] == 0 then 0
					when row[:available_days].nil? then 1
					else 2 + row[:available_days]
					end
				end
				{ theme: theme, platforms: sorted_rows }
			end.sort_by do |group|
				# 主题组排序：取该主题下最紧急的项作为排序键
				min_weight = group[:platforms].map { |row|
					case
					when row[:pending] == 0 then 0
					when row[:available_days].nil? then 1
					else 2 + row[:available_days]
					end
				}.min
				min_weight
			end

			{
				work_type: config[:work_type],
				themes: grouped_by_theme
			}
		end
	end

	private

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
