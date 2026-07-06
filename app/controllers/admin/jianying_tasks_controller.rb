class Admin::JianyingTasksController < Admin::BaseController
	before_action :set_jianying_task, only: [:show, :destroy]

	def index
		@q = JianyingTask.ransack(params[:q])
		@jianying_tasks = @q.result(distinct: true)
		                   .order(created_at: :desc)
		                   .page(params[:page])
		                   .per(15)
	end

	def show
	end

	def destroy
		if @jianying_task.pending?
			@jianying_task.destroy
			redirect_to admin_jianying_tasks_path, notice: "任务删除成功"
		else
			redirect_to admin_jianying_tasks_path, alert: "仅待分配状态的任务可以删除"
		end
	end

	private

	def set_jianying_task
		@jianying_task = JianyingTask.find(params[:id])
	end
end
