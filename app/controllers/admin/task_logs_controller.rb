class Admin::TaskLogsController < Admin::BaseController
	def index
		@q = TaskLog.ransack(params[:q])
		@task_logs = @q.result(distinct: true)
		               .includes(move_task: [:account, :browser], jianying_task: [:account, :browser], grok_task: [:account, :browser], operation_task: [:account, :browser])
		               .order(run_at: :desc)
		               .page(params[:page])
		               .per(15)
		@work_types = Account.work_types.keys
	end

	def show
		@task_log = TaskLog.find(params[:id])
	end
end
