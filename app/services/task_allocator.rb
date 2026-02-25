class TaskAllocator
	class << self
		# 为单个任务分配账号（任务必须包含 platform）
		def allocate(task)
			return false unless task.pending?
			return false unless task.platform.present?

			# 查找该主题 + 该平台下的可用账号（最久未使用）
			account = Account.available_for_theme_and_platform(task.theme, task.platform).first
			return false unless account

			ActiveRecord::Base.transaction do
				account.lock!
				task.update!(
					account_id: account.id,
					browser_id: account.browser_id,
					status: :waiting_publish,
				)
				# 分配即记录（调度语义）
				account.update!(last_used_at: Time.current)
				account.mark_as_assigned!
			end
			true
		rescue => e
			Rails.logger.error "任务分配失败 task_id=#{task.id}: #{e.message}"
			false
		end
	end
end