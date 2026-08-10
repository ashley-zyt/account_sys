class WarmupScheduler
  # 单次请求最长10分钟
  TIMEOUT_SECONDS = 660
  # 账号间等待时间
  INTER_ACCOUNT_PAUSE_MIN = 30
  INTER_ACCOUNT_PAUSE_MAX = 60
  # 每台运营机器单次运行时长上限（小时）；超时自动停止，下次从上次位置继续
  TIME_WINDOW_HOURS = 6

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
  def self.run_for_machine(machine_ip)
    start_time = Time.current
    accounts = fetch_target_accounts_for_machine(machine_ip)
    Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 获取到 #{accounts.size} 个需要养号的账号"
    return if accounts.empty?

    accounts.each_with_index do |account, index|
      break if time_exceeded?(start_time, TIME_WINDOW_HOURS)

      execute_warmup_for_account(account, machine_ip)

      if index < accounts.size - 1 && !time_exceeded?(start_time, TIME_WINDOW_HOURS)
        pause_time = rand(INTER_ACCOUNT_PAUSE_MIN..INTER_ACCOUNT_PAUSE_MAX)
        Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 等待 #{pause_time} 秒后处理下一个账号"
        sleep(pause_time)
      end
    end

    Rails.logger.info "[WarmupScheduler] 机器 #{machine_ip} 养号任务执行完成"
  end

  private

  # 当前需要参与养号的所有运营机器 IP（来自浏览器配置）
  def self.target_machine_ips
    Browser.where.not(machine_ip: [nil, ""])
           .joins(:accounts)
           .distinct
           .pluck(:machine_ip)
  end

  # 查询指定机器下需要养号的账号
  # 排序：1) 从未养号优先 2) 上次报错优先 3) 上次养号时间更久优先
  def self.fetch_target_accounts_for_machine(machine_ip)
    browser_ids = Browser.where(machine_ip: machine_ip).pluck(:id)
    Account.joins(:warmup_profile)
           .where(browser_id: browser_ids)
           .where.not(status: ["未登录", "封禁/停用"])
           .where(warmup_profiles: { warmup_enabled: true })
           .order(Arel.sql("warmup_profiles.last_warmup_at IS NULL DESC, warmup_profiles.warmup_status = 'failed' DESC, warmup_profiles.last_warmup_at ASC"))
  end

  def self.execute_warmup_for_account(account, machine_ip)
    return if account.browser.nil?

    endpoint = "http://#{machine_ip}:#{Browser::NURTURE_PORT}/accounts/nurture"
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
        platform: account.platform
      }

      response = send_request(endpoint, request_data)

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
  end

  def self.send_request(endpoint, request_data)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = TIMEOUT_SECONDS
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request.body = request_data.to_json

    begin
      response = http.request(request)
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
