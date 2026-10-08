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

  # 清洗字符串里的非法 UTF-8 字节，避免写 MySQL 时报 Incorrect string value。
  # 合法 UTF-8 原样返回；否则按 UTF-8 重打标签并 scrub 掉非法字节。
  def self.safe_utf8(str)
    return nil if str.nil?
    s = str.to_s
    return s if s.encoding == Encoding::UTF_8 && s.valid_encoding?
    s.dup.force_encoding(Encoding::UTF_8).scrub('')
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

    # 清洗 error_msg 里的非法 UTF-8 字节：postforme 等第三方返回的错误信息可能带
    # 非法字节，直接写 MySQL text 字段会被拒（Incorrect string value）导致 create! 抛异常。
    error_msg = safe_utf8(error_msg)

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

  # 资源失效关键词：命中则视为「媒体/URL 已失效」，任务直接置 failed 终态、不再回 pending。
  # 例：postforme 返回 "All media failed to process, please check media URLS"
  #     下载端返回 "download failed: HTTP 404"
  RESOURCE_INVALID_KEYWORDS = [
    'media failed',
    'check media url',
    'media url',
    'HTTP 404',
    'download failed'
  ].freeze

  # 判断错误信息是否属于「资源失效」（媒体/URL 失效，重新发布也注定失败）
  def self.resource_invalid_error?(error_msg)
    msg = error_msg.to_s.downcase
    RESOURCE_INVALID_KEYWORDS.any? { |kw| msg.include?(kw) }
  end

  # 发布失败上限：累计失败达到该次数即判定资源不可用、置为 failed 终态
  PUBLISH_FAILURE_LIMIT = 4

  # 记录一次发布失败：失败次数 +1；达到上限则置为 failed 终态（不再重新分配）并返回 true，
  # 否则仅累加计数并返回 false。调用方在返回 true 时应终止后续的状态更新。
  def self.record_publish_failure!(task, error_msg = nil)
    count = task.failure_count.to_i + 1
    if count >= PUBLISH_FAILURE_LIMIT
      # 用 update_columns 绕过 account_id presence 校验（这些模型 failed 状态要求账号非空）
      task.update_columns(
        status: task.class.statuses[:failed],
        failure_count: count,
        account_id: nil,
        browser_id: nil,
        error_msg: error_msg.presence || "连续发布失败#{count}次，判定资源不可用",
        start_at: nil,
        updated_at: Time.current
      )
      TaskAssignment.release!(task.task_uuid, error_msg.presence || "连续发布失败#{count}次，判定资源不可用")
      Rails.logger.warn "[TaskReportHelper] #{task.class}##{task.id} 连续发布失败#{count}次，置为 failed 终态"
      true
    else
      task.update_column(:failure_count, count)
      false
    end
  end

  def self.update_task_status(task, status, error_msg = nil)
    error_msg = safe_utf8(error_msg)

    ActiveRecord::Base.transaction do
      if status == 'success'
        task.update!(
          status: :success,
          actual_publish_time: Time.current,
          error_msg: nil
        )
      else
        if WorkMode.for_model(task.class)
          if record_publish_failure!(task, error_msg)
            # 累计失败已达上限：资源已删除，无需再做状态更新
          elsif resource_invalid_error?(error_msg)
            # 资源失效（媒体/URL 已失效，重新发布也注定失败）：直接置 failed 终态，
            # 清空账号/浏览器/开始时间，不再回 pending。
            # 用 update_columns 绕过 account_id presence 校验（这些模型有
            # validates :account_id, presence: true, unless: :pending?，failed 状态要求账号非空）
            task.update_columns(
              status: task.class.statuses[:failed],
              account_id: nil,
              browser_id: nil,
              error_msg: error_msg,
              start_at: nil,
              updated_at: Time.current
            )
            TaskAssignment.release!(task.task_uuid, error_msg.presence || '资源失效，任务终态失败')
          else
            # 其它失败：重置为 pending，清空账号/浏览器/开始时间，等待重新分配
            task.update!(
              status: :pending,
              account_id: nil,
              browser_id: nil,
              error_msg: error_msg,
              start_at: nil
            )
            # 归属已随释放从任务上清空，标进 TaskAssignment 留档（归档日志时还要用）
            TaskAssignment.release!(task.task_uuid, error_msg.presence || '任务失败，重置待重新分配')
          end
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