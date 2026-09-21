class Admin::MoveTasksController < Admin::BaseController
	include TaskExecutable

	# 搬运资源队列：展示所有发布任务
	# （不再按 move_video.status=processed 过滤，兼容 move_video 已清除、move_video_id 为空的孤儿任务）
	def index
		@q = MoveTask.ransack(params[:q])
		@move_tasks = @q.result(distinct: true)
			.includes(:account, :browser, :move_video)
			.order(created_at: :desc)
			.page(params[:page]).per(15)
		@themes = Theme.pluck(:name)
	end

	def show
		@move_task = MoveTask.find(params[:id])
	end

	private

	def task_model_class
		MoveTask
	end
end
