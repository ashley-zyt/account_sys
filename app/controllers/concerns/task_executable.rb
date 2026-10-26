# 任务「立即执行」通用能力
#
# 供各资源队列 controller 复用：给 waiting_publish（等待发布）状态的任务提供「立即执行」入口。
# 子 controller 需：
#   1. include TaskExecutable
#   2. 实现私有方法 task_model_class 返回对应任务模型类（如 MoveTask）
#   3. 路由加 member :post => :execute
module TaskExecutable
  extend ActiveSupport::Concern

  # 立即执行指定任务（异步，避免阻塞页面）
  def execute
    task = task_model_class.find_by(id: params[:id])

    if task.nil?
      redirect_back(fallback_location: admin_root_path, alert: "任务不存在")
      return
    end

    unless task.waiting_publish?
      redirect_back(fallback_location: admin_root_path, alert: "任务当前状态为「#{task.status}」，仅「等待发布」可立即执行")
      return
    end

    # 发布可能耗时数分钟，异步执行避免阻塞 HTTP 请求（与 warmup_tasks#execute 一致）
    task_id  = task.id
    task_cls = task.class
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          fresh_task = task_cls.find_by(id: task_id)
          PublishScheduler.execute_single_task(fresh_task) if fresh_task
        rescue => e
          Rails.logger.error "[TaskExecutable] 任务 #{task_cls}##{task_id} 立即执行异常: #{e.message}"
        end
      end
    end

    redirect_back(fallback_location: admin_root_path, notice: "任务 ##{task_id} 已开始执行")
  end

  # 人工认领：把「待分配/等待发布」的任务改为认领终态，系统不再发布
  def claim
    task = task_model_class.find_by(id: params[:id])

    if task.nil?
      redirect_back(fallback_location: admin_root_path, alert: "任务不存在")
      return
    end

    unless task.pending? || task.waiting_publish?
      redirect_back(fallback_location: admin_root_path, alert: "任务当前状态为「#{task.status}」，仅「待分配/等待发布」可人工认领")
      return
    end

    # 释放归属（若已发活），再置认领终态（清账号/浏览器，绕过 pending 外的 account_id 校验）
    if task.respond_to?(:task_uuid) && task.task_uuid.present?
      TaskAssignment.release!(task.task_uuid, '人工认领')
    end
    task.update_columns(
      status: task.class.statuses[:claimed],
      account_id: nil,
      browser_id: nil,
      error_msg: '人工认领',
      updated_at: Time.current
    )

    redirect_back(fallback_location: admin_root_path, notice: "任务 ##{task.id} 已人工认领，系统不再发布")
  end

  private

  # 子类需覆盖，返回对应任务模型类（如 MoveTask）
  def task_model_class
    raise NotImplementedError, "#{self.class} 需实现 task_model_class 返回任务模型类"
  end
end
