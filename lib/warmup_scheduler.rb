class WarmupScheduler
  # 养号API端点，端口统一8080，IP通过环境变量配置
  # 视频搬运账号使用 MOVE_NURTURE_HOST，其他账号使用 OTHER_NURTURE_HOST
  MOVE_ENDPOINT = "http://#{ENV['MOVE_NURTURE_HOST'] || '174.139.46.117'}:8080/accounts/nurture"
  OTHER_ENDPOINT = "http://#{ENV['OTHER_NURTURE_HOST'] || '174.139.46.15'}:8080/accounts/nurture"

  # 单次请求最长16分钟
  TIMEOUT_SECONDS = 960
  # 账号间等待时间
  INTER_ACCOUNT_PAUSE_MIN = 60
  INTER_ACCOUNT_PAUSE_MAX = 120
  # 单次运行最多处理账号数
  MAX_ACCOUNTS_PER_RUN = 15
  # 单次运行最长时长（小时）
  TIME_WINDOW_HOURS = 2.9

  @@start_time = nil

  def self.run
    Rails.logger.info "[WarmupScheduler] 开始养号任务"

    @@start_time = Time.current
    accounts = fetch_target_accounts
    Rails.logger.info "[WarmupScheduler] 获取到 #{accounts.size} 个需要养号的账号"

    accounts.each_with_index do |account, index|
      break if time_window_exceeded?

      execute_warmup_for_account(account)

      if index < accounts.size - 1 && !time_window_exceeded?
        pause_time = rand(INTER_ACCOUNT_PAUSE_MIN..INTER_ACCOUNT_PAUSE_MAX)
        Rails.logger.info "[WarmupScheduler] 等待 #{pause_time} 秒后处理下一个账号"
        sleep(pause_time)
      end
    end

    Rails.logger.info "[WarmupScheduler] 养号任务执行完成"
  end

  # 查询已启用养号标记的账号，按上次养号时间排序
  # 跳过未登录(1)和封禁/停用(2)的账号
  def self.fetch_target_accounts
    Account.joins(:warmup_profile)
           .where("browser_id IS NOT NULL")
           .where.not(status: ["未登录", "封禁/停用"])
           .where(warmup_profiles: { warmup_enabled: true })
           .order(Arel.sql("warmup_profiles.last_warmup_at IS NULL DESC, warmup_profiles.last_warmup_at ASC"))
           .limit(MAX_ACCOUNTS_PER_RUN)
  end

  # 根据账号工作模式选择养号API端点
  # 视频搬运 → MOVE_ENDPOINT，其他 → OTHER_ENDPOINT
  def self.endpoint_for(account)
    account.work_type == "视频搬运" ? MOVE_ENDPOINT : OTHER_ENDPOINT
  end

  def self.execute_warmup_for_account(account)
    return if account.browser.nil?

    endpoint = endpoint_for(account)
    Rails.logger.info "[WarmupScheduler] 开始养号: #{account.account_name} (#{account.platform}) → #{endpoint}"

    warmup_task = WarmupTask.create!(
      account: account,
      browser: account.browser,
      platform: account.platform,
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
        warmup_task.update!(status: :success, executed_at: Time.current, error_msg: response['info'])
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(last_warmup_at: Time.current, warmup_status: 'success')
      else
        error_msg = response['info'] || '养号失败'
        Rails.logger.error "[WarmupScheduler] 养号失败: #{account.account_name} - #{error_msg}"
        warmup_task.update!(status: :failed, error_msg: error_msg, executed_at: Time.current)
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(warmup_status: 'failed')
      end
    rescue => e
      Rails.logger.error "[WarmupScheduler] 养号异常: #{account.account_name} - #{e.message}"
      warmup_task.update!(status: :failed, error_msg: e.message, executed_at: Time.current)
      profile = account.warmup_profile || account.create_warmup_profile
      profile.update!(warmup_status: 'failed')
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

  def self.time_window_exceeded?
    return false unless @@start_time
    (Time.current - @@start_time) / 3600 >= TIME_WINDOW_HOURS
  end
end
