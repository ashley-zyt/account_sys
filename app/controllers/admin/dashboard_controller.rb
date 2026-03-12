class Admin::DashboardController < Admin::BaseController
	def index
		@accounts_total = Account.count
		@accounts_active = Account.active.count
		@accounts_unlogged = Account.where(status: 1).count
		@accounts_banned = Account.where(status: 2).count
		
		# 今日活跃账号 (通过日志反查)
		today_logs = TaskLog.where("created_at >= ?", Time.zone.now.beginning_of_day).includes(:move_task, :jianying_task)
		@accounts_active_today = today_logs.map { |log| log.task&.account_id }.compact.uniq.count

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

		# 储备任务状况（按主题和平台统计 pending 状态的任务数量）
		@theme_platform_stats = MoveTask.pending.group(:theme, :platform).count.each_with_object({}) do |((theme, platform), count), hash|
			hash[theme] ||= { total: 0 }
			hash[theme][platform] = count
			hash[theme][:total] += count
		end

		# 剪映任务储备状况
		@jianying_theme_platform_stats = JianyingTask.pending.group(:theme, :platform).count.each_with_object({}) do |((theme, platform), count), hash|
			hash[theme] ||= { total: 0 }
			hash[theme][platform] = count
			hash[theme][:total] += count
		end

		# 账号资源分布 (各主题下各平台的活跃账号数量)
		@account_distribution_stats = Account.active.group(:theme, :platform).count.each_with_object({}) do |((theme, platform), count), hash|
			hash[theme] ||= { total: 0 }
			hash[theme][platform] = count
			hash[theme][:total] += count
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

		# 平台成功率统计 (基于最近 1000 条日志)
		recent_logs = TaskLog.order(created_at: :desc).limit(1000)
		@platform_success_rates = recent_logs.each_with_object({}) do |log, hash|
			platform = log.display_platform
			next if platform == "未知"
			hash[platform] ||= { total: 0, success: 0 }
			hash[platform][:total] += 1
			hash[platform][:success] += 1 if log.status == "success"
		end

		# 最近 7 天执行趋势
		@daily_stats = (0..6).to_a.reverse.each_with_object({}) do |i, hash|
			date = i.days.ago.to_date
			start_time = date.beginning_of_day
			end_time = date.end_of_day
			hash[date.strftime("%m-%d")] = {
				success: TaskLog.where(created_at: start_time..end_time, status: "success").count,
				failed: TaskLog.where(created_at: start_time..end_time, status: "failed").count
			}
		end

		# 任务错误信息汇总（按错误内容分组统计）
		@error_summary = TaskLog.failed
		                        .where("created_at >= ?", 7.days.ago)
		                        .where.not(error_msg: [nil, ""])
		                        .group(:error_msg)
		                        .order("count_all DESC")
		                        .limit(5)
		                        .count

		# 最近一周异常账号排行
		@account_failure_ranking = TaskLog.failed
		                                  .where("created_at >= ?", 7.days.ago)
		                                  .group(:account_id)
		                                  .order("count_all DESC")
		                                  .limit(5)
		                                  .count
		                                  .each_with_object([]) do |(account_id, count), arr|
		                                    account = Account.find_by(id: account_id)
		                                    next unless account
		                                    arr << { account: account, failure_count: count }
		                                  end

		@total_logs_count = TaskLog.countend
end
