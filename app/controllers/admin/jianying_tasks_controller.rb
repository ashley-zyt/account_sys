class Admin::JianyingTasksController < Admin::BaseController
	before_action :set_jianying_task, only: [:show]

	def index
		@q = JianyingTask.ransack(params[:q])
		@jianying_tasks = @q.result(distinct: true)
		                   .includes(:account, :browser)
		                   .order(created_at: :desc)
		                   .page(params[:page])
		                   .per(10)
	end

	def show
	end

	private

	def set_jianying_task
		@jianying_task = JianyingTask.find(params[:id])
	end
end
