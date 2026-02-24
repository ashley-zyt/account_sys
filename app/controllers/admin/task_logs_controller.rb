class Admin::TaskLogsController < Admin::BaseController
	def index
		@q = TaskLog.ransack(params[:q])
		@task_logs = @q.result(distinct: true).order(run_at: :desc).page(params[:page]).per(10)
	end

	def show
		@task_log = TaskLog.find(params[:id])
	end
end
