class TaskScheduler
	def self.pending_task
		# 获取所有有 pending 任务的平台（去重）
		platforms_with_pending = MoveTask.where(status: :pending).distinct.pluck(:platform)

		platforms_with_pending.each do |platform|
			MoveTask.pending_for_platform(platform).limit(20).each do |task|
				TaskAllocator.allocate(task)
			end
		end
	end
end