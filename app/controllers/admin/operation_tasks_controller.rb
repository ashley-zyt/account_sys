class Admin::OperationTasksController < Admin::BaseController
	before_action :set_operation_task, only: [:show]

	def index
		@q = OperationTask.ransack(params[:q])
		@operation_tasks = @q.result(distinct: true)
		                   .includes(:account)
		                   .order(created_at: :desc)
		                   .page(params[:page])
		                   .per(10)
	end

	def show
	end

	private

	def set_operation_task
		@operation_task = OperationTask.find(params[:id])
	end
end