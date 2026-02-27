class TaskScheduler
	def self.pending_task
		# 获取所有有 pending 任务的平台（去重）
		# platforms_with_pending = MoveTask.where(status: :pending).distinct.pluck(:platform)

		# platforms_with_pending.each do |platform|
		# 	MoveTask.pending_for_platform(platform).limit(20).each do |task|
		# 		TaskAllocator.allocate(task)
		# 	end
		# end
		Account.active.where(work_type:0).each do |account|
			task = MoveTask.where(status:"pending").where(platform:account.platform).order("created_at asc").first
			if !task.nil?
				task.update(account_id: account.id,browser_id: account.browser_id,status:waiting_publish)
			end
		end
	end
end