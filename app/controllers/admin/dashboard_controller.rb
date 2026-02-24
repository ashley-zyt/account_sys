class Admin::DashboardController < Admin::BaseController
	def index
		@accounts_total = Account.count
		@accounts_active = Account.active.count
		@accounts_unlogged = Account.where(status: 1).count
		@accounts_banned = Account.where(status: 2).count

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

		@recent_tasks = MoveTask.includes(:account, :browser).order(created_at: :desc).limit(10)
	end
end
