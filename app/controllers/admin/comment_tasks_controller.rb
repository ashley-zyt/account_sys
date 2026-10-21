class Admin::CommentTasksController < Admin::BaseController
  def index
    @q = CommentTask.ransack(params[:q])
    @comment_tasks = @q.result
                       .includes(:account, influencer_post: :influencer)
                       .order(created_at: :desc)
                       .page(params[:page])
  end

  # 手动下发单条评论任务到机器端执行
  def execute
    task = CommentTask.find_by(id: params[:id])
    if task.nil?
      redirect_back fallback_location: admin_comment_tasks_path, alert: '评论任务不存在'
      return
    end

    result = CommentPublisher.dispatch(task)
    if result[:success]
      task.update!(status: :queued, machine_task_id: result[:task_id])
      redirect_back fallback_location: admin_comment_tasks_path, notice: "评论任务 ##{task.id} 已下发"
    else
      redirect_back fallback_location: admin_comment_tasks_path, alert: "下发失败：#{result[:error]}"
    end
  end
end
