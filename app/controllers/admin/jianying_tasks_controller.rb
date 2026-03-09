class Admin::JianyingTasksController < Admin::BaseController
	before_action :set_jianying_task, only: [:show, :edit, :update, :destroy]

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

	def new
		@jianying_task = JianyingTask.new
	end

	def create
		@jianying_task = JianyingTask.new(jianying_task_params)
		if @jianying_task.save
			redirect_to admin_jianying_task_path(@jianying_task), notice: "剪映任务已成功创建"
		else
			render :new, status: :unprocessable_entity
		end
	end

	def edit
	end

	def update
		if @jianying_task.update(jianying_task_params)
			redirect_to admin_jianying_task_path(@jianying_task), notice: "剪映任务已成功更新"
		else
			render :edit, status: :unprocessable_entity
		end
	end

	def destroy
		@jianying_task.destroy
		redirect_to admin_jianying_tasks_path, notice: "剪映任务已成功删除"
	end

	private

	def set_jianying_task
		@jianying_task = JianyingTask.find(params[:id])
	end

	def jianying_task_params
		params.require(:jianying_task).permit(
			:oss_url, :task_uuid, :title, :theme, :status, 
			:error_msg, :start_at, :actual_publish_time, 
			:account_id, :browser_id, :platform, :group_id
		)
	end
end
