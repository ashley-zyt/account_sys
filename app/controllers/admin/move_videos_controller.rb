class Admin::MoveVideosController < Admin::BaseController
	# 搬运视频储备：展示所有录入的源视频及其下载/剪映处理进度
	def index
		@q = MoveVideo.ransack(params[:q])
		@move_videos = @q.result(distinct: true)
			.includes(:move_tasks)
			.order(created_at: :desc)
			.page(params[:page]).per(15)
	end

	def show
		@move_video = MoveVideo.find(params[:id])
	end
end
