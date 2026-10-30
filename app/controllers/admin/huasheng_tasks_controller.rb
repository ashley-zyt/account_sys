class Admin::HuashengTasksController < Admin::BaseController
  include TaskExecutable
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

  # 补发「抖音-视频号」合并任务的单个平台（抖音或视频号）
  def republish
    task = HuashengTask.find(params[:id])
    platform_key = params[:platform].to_s
    platform_name = platform_key == "douyin" ? "抖音" : "视频号"

    result = DomesticHuashengPublishWorker.publish(task, platform_key, platform_name)

    if result[:success]
      task.update_columns(
        status: HuashengTask.statuses[:success],
        actual_publish_time: Time.current,
        error_msg: nil,
        updated_at: Time.current
      )
      redirect_to admin_huasheng_tasks_path, notice: "#{platform_name}补发成功"
    else
      task.update_columns(
        error_msg: "补发#{platform_name}失败(#{result[:message]})",
        updated_at: Time.current
      )
      redirect_to admin_huasheng_tasks_path, alert: "#{platform_name}补发失败: #{result[:message]}"
    end
  end

  private

  def task_model_class
    HuashengTask
  end

  def set_huasheng_task
    @huasheng_task = HuashengTask.find(params[:id])
  end
end
