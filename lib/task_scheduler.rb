class TaskScheduler
	def self.pending_task
		# 释放亨亨猫类型的错误资源
		TaskLog.where(status: "failed").where("error_msg like '%哼哼猫%' or error_msg like '%亨亨猫%'").where("created_at > ?",Time.now-1.days).each do |task_log|
			task = MoveTask.find_by(task_uuid:task_log.task_uuid)
			if task.error_msg.include?"哼哼猫" or task.error_msg.include?"亨亨猫"
				task.update(status:"pending",error_msg:nil,start_at:nil,actual_publish_time:nil,browser_id:nil)
			end
		end
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
				status: :completed,
				actual_publish_time: today_start..today_end
			)

			next if has_posted_today

			pending_task = OperationTask.where(status: :pending, platform: account.platform).order(created_at: :asc).first

			if pending_task
				ActiveRecord::Base.transaction do
					pending_task.update!(
						account_id: account.id,
						browser_id: account.browser_id,
						status: :processing
					)
				end
				Rails.logger.info "人工运营账号 #{account.account_name}[#{account.platform}] 分配运营资源成功"
			else
				Rails.logger.warn "人工运营账号 #{account.account_name}[#{account.platform}] 暂无可用运营资源"
			end
		end
	end
end