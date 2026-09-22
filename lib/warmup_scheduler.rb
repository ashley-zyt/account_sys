class WarmupScheduler
  # 单次请求最长7分钟
  TIMEOUT_SECONDS = 420
  # 账号间等待时间
  INTER_ACCOUNT_PAUSE_MIN = 20
  INTER_ACCOUNT_PAUSE_MAX = 40
  # 每台运营机器单次运行时长上限（小时）；超时自动停止，下次从上次位置继续
  TIME_WINDOW_HOURS = 6
  # 每台机器单次运行最多下发的养号账号数。
  # 机器端全局并发才 3，一次性把整台机器的账号全下发会瞬间堆积卡死，
  # 故每轮（每小时）每台机器最多下发 5 个，下发完即结束，下一轮按顺序取下一批。
  MAX_ACCOUNTS_PER_MACHINE = 9
  # 养号任务卡在 executing 超过此时长（小时）仍无回调，判定为中断，标 failed 释放账号
  STUCK_TIMEOUT_HOURS = 3

  # 统一入口：按 browser.machine_ip 分组，多台机器并行运行、互不影响
  def self.run
    machine_ips = target_machine_ips
    Rails.logger.info "[WarmupScheduler] 发现 #{machine_ips.size} 台运营机器: #{machine_ips.join(', ')}"

    # 提示存在未设置 machine_ip 的浏览器（其账号本轮会被跳过）
    orphan_accounts = Account.joins(:browser)
                             .where.not(status: ["未登录", "封禁/停用"])
                             .where(browsers: { machine_ip: [nil, ""] })
                             .count
    if orphan_accounts > 0
      Rails.logger.warn "[WarmupScheduler] 有 #{orphan_accounts} 个账号的浏览器未设置 machine_ip，本轮跳过，请在浏览器页面补全机器IP"
    end

    return if machine_ips.empty?

    threads = machine_ips.map do |ip|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          run_for_machine(ip)
        end
      end
    end
    threads.each(&:join)
    Rails.logger.info "[WarmupScheduler] 所有机器养号任务执行完成"
  end

  # 针对单台机器运行（公开方法，便于单独触发或调试）
  # 跳过忙的浏览器，优先养号空闲的，忙的账号回头再试
  def self.run_for_machine(machine_ip)
    start_time = Time.current
    accounts = fetch_target_accounts_for_machine(machine_ip)
    Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 获取到 #{accounts.size} 个需要养号的账号"
    return if accounts.empty?

    pending = accounts
    until pending.empty? || time_exceeded?(start_time, TIME_WINDOW_HOURS)
      progressed = false
      still_busy = []

      pending.each do |account|
        status = execute_warmup_for_account(account, machine_ip)
        case status
        when :executed
          progressed = true
          pause_time = rand(INTER_ACCOUNT_PAUSE_MIN..INTER_ACCOUNT_PAUSE_MAX)
          Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 等待 #{pause_time} 秒后处理下一个账号"
          sleep(pause_time)
        when :busy
          still_busy << account
        end
        # :skipped（无浏览器等）直接丢弃
      end

      break if still_busy.empty?
      pending = still_busy
      sleep(10) unless progressed
    end

    Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 养号任务执行完成"
  end

  # 卡死超时兜底：养号任务下发后长时间仍处于 executing（机器端中断/重启/任务丢失
  # 导致永远无回调），把它们标 failed 并释放账号，让账号下一轮重新被选中养号。
  # 配合「成功回调才更新 last_warmup_at」实现养号中断自愈。
  # @return [Integer] 回收的卡死任务数
  def self.recover_stuck_tasks
    stuck = WarmupTask.where(status: :executing)
                      .where('created_at <= ?', STUCK_TIMEOUT_HOURS.hours.ago)
    return 0 if stuck.empty?

    count = 0
    stuck.find_each do |task|
      task.update!(status: :failed,
                   error_msg: "养号中断超时（超过 #{STUCK_TIMEOUT_HOURS} 小时未收到回调）",
                   executed_at: Time.current)
      # 标 warmup_status=failed，让排序「失败优先」下一轮优先重试；
      # 不更新 last_warmup_at，避免中断账号进入冷却而永远不被重选。
      if (profile = task.account&.warmup_profile)
        profile.update!(warmup_status: 'failed')
      end
      count += 1
    end
    Rails.logger.info "[WarmupScheduler] 回收卡死养号任务 #{count} 条"
    count
  end

  private

  # 当前需要参与养号的所有运营机器 IP（来自浏览器配置）
  def self.target_machine_ips
    Browser.where.not(machine_ip: [nil, ""])
           .joins(:accounts)
           .distinct
           .pluck(:machine_ip)
  end

  # 查询指定机器下需要养号的账号（每台机器单次最多 MAX_ACCOUNTS_PER_MACHINE 个）
  # 排除「已有执行中(executing)养号任务」的账号：靠它实现每轮顺序轮转不重复
  #   （刚下发的账号已有 executing 记录，下一轮被跳过，取到下一批）。
  # 排序：1) 从未养号优先 2) 上次报错优先 3) 上次养号时间更久优先
  def self.fetch_target_accounts_for_machine(machine_ip)
    browser_ids = Browser.where(machine_ip: machine_ip).pluck(:id)
    executing_account_ids = WarmupTask.where(status: :executing).select(:account_id)
    Account.joins(:warmup_profile)
           .where(browser_id: browser_ids)
           .where.not(status: ["未登录", "封禁/停用"])
           .where.not(id: executing_account_ids)
           .where(warmup_profiles: { warmup_enabled: true })
           .order(Arel.sql("warmup_profiles.last_warmup_at IS NULL DESC, warmup_profiles.warmup_status = 'failed' DESC, warmup_profiles.last_warmup_at ASC"))
           .limit(MAX_ACCOUNTS_PER_MACHINE)
  end

  # 养号单个账号（异步下发）
  # @return [Symbol] :executed（已执行）/ :skipped（无浏览器）
  def self.execute_warmup_for_account(account, machine_ip)
    return :skipped if account.browser.nil?

    endpoint = "https://#{machine_ip}/accounts/nurture"

    Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 开始养号: #{account.account_name} (#{account.platform}) → #{endpoint}"

    warmup_task = WarmupTask.create!(
      account: account,
      browser: account.browser,
      platform: account.platform,
      machine: machine_ip,
      status: :executing
    )

    begin
      request_data = {
        profile_name: account.browser.profile_name,
        platform: account.platform,
        # 异步模式：机器端立即返回 accepted+task_id，后台执行，完成后回调 /api/v1/browser_tasks/result
        async: true,
        # 业务透传标识：回调时机器端原样带回，用于精确定位到本养号任务
        ref: "WarmupTask:#{warmup_task.id}"
      }

      response = send_request(endpoint, request_data)

      # 异步受理：机器端后台执行中，等 /api/v1/browser_tasks/result 回调再更新状态
      if response['type'] == 'accepted'
        BrowserTaskRecord.track!(
          machine_task_id: response['task_id'],
          ref: "WarmupTask:#{warmup_task.id}",
          task_type: 'nurture',
          profile_name: account.browser.profile_name,
          machine_ip: machine_ip
        )
        # 注意：这里【不再】下发即更新 last_warmup_at。轮转去重改由
        # 「fetch_target_accounts_for_machine 排除 executing 账号」保证；
        # last_warmup_at 只在机器端回调成功/失败后（handle_warmup）才更新，
        # 这样养号中断（无回调）的账号不会进入冷却，下一轮能被重新选中自愈。
        Rails.logger.info "[WarmupScheduler] 养号已受理（异步），task_id=#{response['task_id']}，等待回调"
        return :executed
      end

      # 同步兜底（机器端未启用 async 时）：按原逻辑立即更新
      if response['status'] == 'success'
        Rails.logger.info "[WarmupScheduler] 养号成功: #{account.account_name} - #{response['info']}"
        # 从 info 中提取总时长（秒），如 "总时长 720 秒, 浏览帖子: 30, 点赞: 1, 评论: 7, 关注: 0"
        duration_minutes = nil
        if response['info'] =~ /总时长\s*(\d+)\s*秒/
          total_seconds = $1.to_i
          duration_minutes = (total_seconds / 60.0).round(1)
        end
        warmup_task.update!(status: :success, executed_at: Time.current, error_msg: response['info'], duration_minutes: duration_minutes)
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(last_warmup_at: Time.current, warmup_status: 'success')
      else
        error_msg = response['info'] || '养号失败'
        Rails.logger.error "[WarmupScheduler] 养号失败: 机器 #{machine_ip} / 账号 #{account.account_name} / 原因: #{error_msg}"
        warmup_task.update!(status: :failed, error_msg: error_msg, executed_at: Time.current)
        profile = account.warmup_profile || account.create_warmup_profile
        # 即使失败也更新 last_warmup_at，避免无限重试
        profile.update!(warmup_status: 'failed', last_warmup_at: Time.current)
      end
    rescue => e
      Rails.logger.error "[WarmupScheduler] 养号异常: 机器 #{machine_ip} / 账号 #{account.account_name} / 原因: #{e.message}"
      warmup_task.update!(status: :failed, error_msg: e.message, executed_at: Time.current)
      profile = account.warmup_profile || account.create_warmup_profile
      profile.update!(warmup_status: 'failed', last_warmup_at: Time.current)
    end

    :executed
  end

  def self.send_request(endpoint, request_data)
    begin
      response = RemoteApiClient.post(endpoint, request_data, read_timeout: TIMEOUT_SECONDS)
      JSON.parse(response.body)
    rescue Net::ReadTimeout
      { 'status' => 'error', 'info' => '请求超时' }
    rescue JSON::ParserError => e
      { 'status' => 'error', 'info' => "响应解析失败: #{response&.body}" }
    rescue => e
      { 'status' => 'error', 'info' => "请求异常: #{e.message}" }
    end
  end

  def self.time_exceeded?(start_time, time_window_hours)
    return false unless start_time
    (Time.current - start_time) / 3600 >= time_window_hours
  end
end
