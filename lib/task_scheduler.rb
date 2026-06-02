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
	end
end