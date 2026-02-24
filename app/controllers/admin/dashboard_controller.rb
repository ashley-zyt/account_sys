class Admin::DashboardController < Admin::BaseController
	def index
		@accounts_total = Account.count
		@accounts_active = Account.active.count
		@move_tasks_total = MoveTask.count
		@move_tasks_pending = MoveTask.pending.count
		@move_tasks_waiting = MoveTask.waiting_publish.count
		@move_tasks_executing = MoveTask.executing.count
		@move_tasks_success = MoveTask.success.count
		@move_tasks_failed = MoveTask.failed.count
		@recent_tasks = MoveTask.includes(:account, :browser).order(created_at: :desc).limit(10)
	end
end
