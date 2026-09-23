class Admin::HunjianTasksController < Admin::BaseController
  include TaskExecutable

  # 搬运混剪资源队列：展示所有混剪发布任务
  def index
    @q = HunjianTask.ransack(params[:q])
    @hunjian_tasks = @q.result(distinct: true)
      .includes(:account, :browser)
      .order(created_at: :desc)
      .page(params[:page]).per(15)
    @themes = Theme.pluck(:name)
  end

  def show
    @hunjian_task = HunjianTask.find(params[:id])
  end

  private

  def task_model_class
    HunjianTask
  end
end
