class Admin::HuashengTasksController < Admin::BaseController
  before_action :set_huasheng_task, only: [:show, :destroy]

  def index
    @q = HuashengTask.ransack(params[:q])
    @huasheng_tasks = @q.result(distinct: true)
                        .order(created_at: :desc)
                        .page(params[:page])
                        .per(20)
  end

  def show
    @video_url = HuashengTask.oss_v1_sign_url(@huasheng_task.full_oss_url)
  end

  def destroy
    if @huasheng_task.pending?
      @huasheng_task.destroy
      redirect_to admin_huasheng_tasks_path, notice: "任务删除成功"
    else
      redirect_to admin_huasheng_tasks_path, alert: "仅待分配状态的任务可以删除"
    end
  end

  def batch_destroy
    ids = params[:task_ids]
    if ids.blank?
      redirect_to admin_huasheng_tasks_path, alert: "请选择要删除的任务"
      return
    end

    ids = ids.is_a?(Array) ? ids : ids.split(",")
    tasks = HuashengTask.where(id: ids)

    success_count = 0
    fail_count = 0
    tasks.each do |task|
      if task.pending?
        task.destroy
        success_count += 1
      else
        fail_count += 1
      end
    end

    notice = "批量删除完成：成功 #{success_count} 条"
    notice += "，#{fail_count} 条非待分配状态无法删除" if fail_count > 0
    redirect_to admin_huasheng_tasks_path, notice: notice
  end

  private

  def set_huasheng_task
    @huasheng_task = HuashengTask.find(params[:id])
  end
end
