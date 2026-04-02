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
end