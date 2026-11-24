class Admin::PureMoveTasksController < Admin::BaseController
  include TaskExecutable

  # 纯搬运资源队列：展示所有纯搬运发布任务
  def index
    @q = PureMoveTask.ransack(params[:q])
    @pure_move_tasks = @q.result(distinct: true)
      .includes(:account, :browser, :move_video)
      .order(created_at: :desc)
      .page(params[:page]).per(15)
    @themes = Theme.pluck(:name)
  end

  def show
    @pure_move_task = PureMoveTask.find(params[:id])
  end

  private

  def task_model_class
    PureMoveTask
  end
end
