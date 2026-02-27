class Admin::MoveTasksController < Admin::BaseController
	def index
		@q = MoveTask.ransack(params[:q])
		@move_tasks = @q.result(distinct: true).includes(:account, :browser).order(actual_publish_time: :desc).page(params[:page]).per(10)
	end

	def show
		@move_task = MoveTask.find(params[:id])
	end
end
