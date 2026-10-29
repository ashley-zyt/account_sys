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

  def self.create_task_log(task, status, snapshot_account_id, snapshot_browser_id, error_msg = nil, raw_response = nil, publish_channel = nil)
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
    raw_response = safe_utf8(raw_response)

    log = TaskLog.create!(
      task_uuid: task.task_uuid,
      account_id: snapshot_account_id,
      browser_id: snapshot_browser_id,
      response_data: raw_response.presence || { status: status, error_msg: error_msg }.to_s,
      status: task_status,
      error_msg: error_msg,
      publish_channel: publish_channel,
      run_at: Time.current
    )

    # 同步写入「每日发布对账」：把发布结果当场落到 account_publish_dailies，供日报聚合。
    # account_id 拿不到（任务释放且无归属快照）时跳过，不写对账。
    AccountPublishDaily.record_publish_result!(
      snapshot_account_id,
      task_status,
      error_msg: error_msg,
      task_log_id: log.id
    )

    if error_msg.present?
      check_account_abnormal(snapshot_account_id, error_msg, source_action: '发布')
      check_hhcat_login_failure
    end
  end

  # 账号/浏览器网络问题关键词 → 异常类型（封禁/未登录/网络/其他）。
  # 命中即判「账号有问题」→ 全局封禁（status=封禁/限制），而非资源问题，也不累计资源失败次数。
  # 供发布 / 采集 / 私信 / 养号 四处共用的统一判定口径。
  ABNORMAL_KEYWORD_MAP = {
    banned: [
      "suspended",
      "account banned or human verification required",
      "账号封禁",
      "触发安全风控"
    ],
    logged_out: [
      "not logged in",
      "账号未登录"
    ],
    network: [
      "ERR_PROXY_CONNECTION_FAILED"
    ],
    other: [
      "account verification",
      "some of your media failed to upload",
      "account verification required after upload",
      "Confirm you're human",
      "could not authenticate you",
      "账号验证"
    ]
  }.freeze

  # 判断错误信息是否属于「账号/浏览器网络问题」（账号被封、未登录、代理失效等）
  def self.account_abnormal_error?(error_msg)
    !classify_abnormal(error_msg).nil?
  end

  # 返回 [abnormal_type_symbol, matched_keyword]；未命中返回 nil
  def self.classify_abnormal(error_msg)
    msg = error_msg.to_s
    ABNORMAL_KEYWORD_MAP.each do |type, keywords|
      kw = keywords.find { |k| msg.include?(k) }
      return [type, kw] if kw
    end
    nil
  end

  def self.check_account_abnormal(account_id, error_msg, source_action: nil)
    return unless account_id.present?

    type_kw = classify_abnormal(error_msg)
    return unless type_kw

    type, kw = type_kw
    mark_account_banned!(account_id, abnormal_type: type, matched_keyword: kw, error_msg: error_msg, source_action: source_action)
  end

  # 封禁账号并全局同步：用 update! 触发 after_save 回调，
  # 同步浏览器「无效」状态 + 关闭该账号养号（warmup_enabled=false）。
  # 发布/采集/私信/养号四处共用的统一封禁入口，并落一条 AccountChangeLog 记录。
  def self.mark_account_banned!(account_id, abnormal_type: nil, matched_keyword: nil, error_msg: nil, source_action: nil)
    return false if account_id.blank?

    account = Account.find_by(id: account_id)
    return false unless account
    return false if account.status.in?(["封禁/限制", "停用"])

    # 先记录异常事件（旁路，失败不影响封禁主流程）
    AccountChangeLog.record!(
      account: account,
      change_source: :system,
      abnormal_type: abnormal_type,
      changes: [{ field: "status", from: account.status, to: "封禁/限制" }],
      source_action: source_action,
      matched_keyword: matched_keyword,
      error_msg: error_msg,
      changed_at: Time.current
    )

    account.update!(status: "封禁/限制")
    Rails.logger.warn "[TaskReportHelper] 账号 #{account_id} 检测到异常，已全局封禁（status=封禁/限制）"
    true
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

  # 渠道降级：发布失败（资源有问题/渠道错误/超时）后 failure_count+1，保留账号回 waiting_publish，
  # 下一次发布走下一层渠道（同一个视频换渠道，账号不变）。
  # 终态（所有可用渠道都试过）由 PublishScheduler.attempt_task 在路由时判定
  # （channel 为 nil → failed），这里不做终态判断，只返回 true 表示「需要重新发布」。
  def self.downgrade_task(task, error_msg)
    task.update!(
      status: :waiting_publish,
      error_msg: error_msg,
      failure_count: task.failure_count.to_i + 1,
      start_at: nil
    )
    true
  end

  def self.update_task_status(task, status, error_msg = nil)
    error_msg = safe_utf8(error_msg)
    retry_after = false

    ActiveRecord::Base.transaction do
      if status == 'success'
        task.update!(
          status: :success,
          actual_publish_time: Time.current,
          error_msg: nil
        )
      else
        if WorkMode.for_model(task.class)
          if resource_invalid_error?(error_msg)
            # 资源失效（媒体/URL 已失效，重新发布也注定失败）：直接置 failed 终态，
            # 不累计失败次数，清空账号/浏览器/开始时间，不再回 pending。
            fail_task_terminal(task, error_msg, '资源失效，任务终态失败')
          elsif account_abnormal_error?(error_msg)
            # 账号/浏览器网络问题：回 pending 换账号重试，不降级不累计失败次数。
            # 账号封禁由 create_task_log 里的 check_account_abnormal 统一处理。
            reset_task_to_pending(task, error_msg)
          else
            # 渠道/资源失败（含资源有问题、超时、渠道错误）：降级到下一层渠道并触发重新发布。
            retry_after = downgrade_task(task, error_msg)
          end
        else
          task.update!(
            status: :failed,
            error_msg: error_msg
          )
        end
      end
    end

    # 事务提交后再触发重新发布：避免在事务内下发，且只对「降级」分支生效。
    # attempt_task 内部会按 failure_count 取下一渠道；渠道耗尽则直接置 failed。
    PublishScheduler.retry_task(task) if retry_after
  end

  # 任务置 failed 终态：用 update_columns 绕过 account_id presence 校验
  # （这些模型有 validates :account_id, presence: true, unless: :pending?，failed 状态要求账号非空）
  def self.fail_task_terminal(task, error_msg, release_reason)
    task.update_columns(
      status: task.class.statuses[:failed],
      account_id: nil,
      browser_id: nil,
      error_msg: error_msg,
      start_at: nil,
      updated_at: Time.current
    )
    TaskAssignment.release!(task.task_uuid, error_msg.presence || release_reason)
  end

  # 任务回 pending：清空账号/浏览器/开始时间，等待重新分配（换账号重试）
  def self.reset_task_to_pending(task, error_msg)
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

end