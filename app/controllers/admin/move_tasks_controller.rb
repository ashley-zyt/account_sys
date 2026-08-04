class Admin::MoveTasksController < Admin::BaseController
	# 搬运资源队列：主要展示已剪映处理完成（move_video.status = processed）的发布任务
	def index
		@q = MoveTask.ransack(params[:q])
		@move_tasks = @q.result(distinct: true)
			.includes(:account, :browser, :move_video)
			.where(move_videos: { status: MoveVideo.statuses[:processed] })
			.references(:move_videos)
			.order(created_at: :desc)
			.page(params[:page]).per(15)
	end

	def show
		@move_task = MoveTask.find(params[:id])
	end
end
