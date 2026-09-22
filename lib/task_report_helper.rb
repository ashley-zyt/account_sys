# 任务报告帮助模块
# 提取 report 接口中的业务逻辑，供发布调度器等其他模块复用
module TaskReportHelper

  # 取执行归属快照（账号 / 浏览器）。
  #
  # 2026-09-22 新增：任务被中断释放后回调才到，任务上的 account_id / browser_id 已被清空，
  # 只靠 task.account_id 会让 task_logs 对不上账号和浏览器（任务若已被重新分配还会记成别人）。
  # 因此先读任务上的当前值，为空时回退到 TaskAssignment（发活那一刻固化的归属）。
  #
  # @return [Array<(Integer|nil, String|nil)>] [account_id, browser_id]
  def self.resolve_snapshot(task)
    account_id = task.account_id
    browser_id = task.browser_id

    if account_id.blank? || browser_id.blank?
      snap = TaskAssignment.snapshot_for(task.task_uuid)
      account_id ||= snap&.account_id
      browser_id ||= snap&.browser_id
    end

    [account_id, browser_id]
  end

  def self.create_task_log(task, status, snapshot_account_id, snapshot_browser_id, error_msg = nil)
    task_status = status == 'success' ? "success" : "failed"

    # 兜底：调用方传进来的快照可能为空（任务在回调前已被释放）。
    # 此时从 TaskAssignment（发活时固化的归属）里补回来，避免日志对不上账号/浏览器。
    if snapshot_account_id.blank? || snapshot_browser_id.blank?
      fallback_account_id, fallback_browser_id = resolve_snapshot(task)
      snapshot_account_id ||= fallback_account_id
      snapshot_browser_id ||= fallback_browser_id
    end

    TaskLog.create!(
      task_uuid: task.task_uuid,
      account_id: snapshot_account_id,
      browser_id: snapshot_browser_id,
      response_data: { status: status, error_msg: error_msg }.to_s,
      status: task_status,
      error_msg: error_msg,
      run_at: Time.current
    )

    if error_msg.present?
      check_account_abnormal(snapshot_account_id, error_msg)
      check_hhcat_login_failure
    end
  end

  def self.check_account_abnormal(account_id, error_msg)
    return unless account_id.present?

    abnormal_keywords = [
      "not logged in",
      "account verification",
      "some of your media failed to upload",
      "account banned or human verification required",
      "account verification required after upload",
      "Confirm you're human",
      "账号未登录",
      "账号验证",
      "账号封禁"
    ]

    if abnormal_keywords.any? { |keyword| error_msg.include?(keyword) }
      Account.where(id: account_id).update_all(status: 2)
      Rails.logger.warn "[TaskReportHelper] 账号 #{account_id} 检测到异常，已标记为异常状态"
    end
  end

  def self.check_hhcat_login_failure
    five_minutes_ago = Time.current - 5.minutes
    recent_errors = TaskLog.where("error_msg LIKE '%哼哼猫未登陆成功%' AND created_at >= ?", five_minutes_ago).order(id: :desc).limit(5)

    if recent_errors.size >= 5
      # 批量回退前先把这批任务的归属标为已释放（不删记录），
      # 这样它们迟到的回调仍能通过 TaskAssignment 认到原来的账号/浏览器。
      [OperationTask, MoveTask].each do |model|
        scope = model.where(status: :waiting_publish)
        TaskAssignment.release_many!(scope.pluck(:task_uuid), '哼哼猫连续未登录，批量回退待重新分配')
        scope.update_all(
          status: :pending,
          account_id: nil,
          browser_id: nil
        )
      end
    end
  end

  def self.update_task_status(task, status, error_msg = nil)
    ActiveRecord::Base.transaction do
      if status == 'success'
        task.update!(
          status: :success,
          actual_publish_time: Time.current,
          error_msg: nil
        )
      else
        # 所有资源队列任务失败时统一重置为 pending，清空账号/浏览器/开始时间，等待重新分配
        if WorkMode.for_model(task.class)
          task.update!(
            status: :pending,
            account_id: nil,
            browser_id: nil,
            error_msg: error_msg,
            start_at: nil
          )
          # 归属已随释放从任务上清空，标进 TaskAssignment 留档（归档日志时还要用）
          TaskAssignment.release!(task.task_uuid, error_msg.presence || '任务失败，重置待重新分配')
        else
          task.update!(
            status: :failed,
            error_msg: error_msg
          )
        end
      end
    end
  end

end