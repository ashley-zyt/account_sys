class Admin::CommentTasksController < Admin::BaseController
  def index
    @q = CommentTask.ransack(params[:q])
    @comment_tasks = @q.result
                       .includes(:influencer_post, :account)
                       .order(created_at: :desc)
                       .page(params[:page])
  end
end
