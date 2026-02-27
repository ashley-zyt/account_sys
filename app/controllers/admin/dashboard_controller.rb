class Admin::DashboardController < Admin::BaseController
	def index
		@accounts_total = Account.count
		@accounts_active = Account.active.count
		@accounts_unlogged = Account.where(status: 1).count
		@accounts_banned = Account.where(status: 2).count

		# 按平台统计
		@platform_stats = Account.group(:platform, :status).count.each_with_object({}) do |((platform, status), count), hash|
			hash[platform] ||= { total: 0, active: 0, unlogged: 0, banned: 0 }
			hash[platform][:total] += count
			case status
			when "正常" then hash[platform][:active] += count
			when "未登录" then hash[platform][:unlogged] += count
			when "封禁/停用" then hash[platform][:banned] += count
			end
		end

		# 资源储备分布（按主题统计账号使用情况）
		today_beginning = Time.zone.now.beginning_of_day
		active_accounts = Account.active
		theme_totals = active_accounts.group(:theme).count
		theme_used = active_accounts.where("last_used_at >= ?", today_beginning).group(:theme).count

		@theme_resource_stats = theme_totals.each_with_object({}) do |(theme, total), hash|
			u_count = theme_used[theme] || 0
			hash[theme] = {
				total: total,
				used: u_count,
				to_be_used: total - u_count
			}
		end

		@browsers_total = Browser.count
		@browsers_normal = Browser.where(status: 0).count
		@browsers_network_error = Browser.where(status: 1).count

		@move_tasks_total = MoveTask.count
		@move_tasks_pending = MoveTask.pending.count
		@move_tasks_waiting = MoveTask.waiting_publish.count
		@move_tasks_executing = MoveTask.executing.count
		@move_tasks_success = MoveTask.success.count
		@move_tasks_failed = MoveTask.failed.count

		@today_logs_count = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).count
		@today_errors_count = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).failed.count

		@total_logs_count = TaskLog.count
		@total_errors_count = TaskLog.failed.count

		# 任务错误信息汇总（按错误内容分组统计）
		@error_summary = MoveTask.failed
		                        .where.not(error_msg: [nil, ""])
		                        .group(:error_msg)
		                        .order("count_all DESC")
		                        .limit(5)
		                        .count
	end
end
