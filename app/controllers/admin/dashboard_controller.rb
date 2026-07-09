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
	end

	private

	def fetch_abnormal_accounts(_min_consecutive_failures)
		error_counts = TaskLog.failed
			.joins(:log_account)
			.where("account_id IS NOT NULL")
			.where("run_at >= ?", 1.week.ago)
			.where(accounts: { status: "正常" })
			.group(:account_id)
			.order("COUNT(*) DESC")
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
