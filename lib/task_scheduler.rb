class TaskScheduler
	def self.pending_task
		Account.active.where(work_type:0).each do |account|
			task = MoveTask.where(status:"pending").where(platform:account.platform,theme:account["theme"]).order("created_at asc").first
			if !task.nil?
				task.update(account_id: account.id,browser_id: account.browser_id,status:"waiting_publish")
			end
		end
	end
end