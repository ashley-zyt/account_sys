class WarmupScheduler
  PLATFORM_ENDPOINTS = {
    facebook: 'http://174.139.46.15:8080/facebook/warmup',
    twitter: 'http://174.139.46.15:8080/twitter/warmup',
    youtube: 'http://174.139.46.15:8080/youtube/warmup',
    tiktok: 'http://174.139.46.15:8080/tiktok/warmup',
    instagram: 'http://174.139.46.15:8080/instagram/warmup'
  }

  OPERATIONS = {
    browse: '浏览帖子',
    like: '点赞',
    follow: '关注',
    comment: '评论',
    share: '分享'
  }

  TIMEOUT_SECONDS = 900
  ACCOUNT_DURATION_MIN = 10
  ACCOUNT_DURATION_MAX = 15
  INTER_ACCOUNT_PAUSE_MIN = 60
  INTER_ACCOUNT_PAUSE_MAX = 120

  MAX_ACCOUNTS_PER_NIGHT = 15
  TIME_WINDOW_HOURS = 2.9
  START_TIME_HOUR = 0

  @@start_time = nil

  def self.run(machine = nil)
    machine = detect_machine if machine.nil?
    Rails.logger.info "[WarmupScheduler] 开始养号任务，机器: #{machine}"

    @@start_time = Time.current
    accounts = fetch_target_accounts(machine)
    Rails.logger.info "[WarmupScheduler] 获取到 #{accounts.size} 个需要养号的账号"

    accounts.each_with_index do |account, index|
      break if time_window_exceeded?

      execute_warmup_for_account(account, machine)

      if index < accounts.size - 1 && !time_window_exceeded?
        pause_time = rand(INTER_ACCOUNT_PAUSE_MIN..INTER_ACCOUNT_PAUSE_MAX)
        Rails.logger.info "[WarmupScheduler] 等待 #{pause_time} 秒后处理下一个账号"
        sleep(pause_time)
      end
    end

    advance_batch(machine)
    Rails.logger.info "[WarmupScheduler] 养号任务执行完成"
  end

  def self.detect_machine
    env_machine = ENV['WARMUP_MACHINE']&.downcase&.to_sym
    return env_machine if env_machine && [:move, :other].include?(env_machine)

    hostname = `hostname`.strip rescue 'unknown'
    if hostname.include?('move') || hostname.include?('video')
      :move
    else
      :other
    end
  end

  def self.fetch_target_accounts(machine)
    current_batch = get_current_batch(machine)
    Rails.logger.info "[WarmupScheduler] 当前批次: #{current_batch}"

    base_scope = Account.active.where("browser_id IS NOT NULL")

    case machine
    when :move
      base_scope.where(work_type: "视频搬运")
    when :other
      base_scope.where.not(work_type: "视频搬运")
    else
      base_scope
    end

    base_scope.where(warmup_batch: current_batch)
              .order(last_warmup_at: :asc, created_at: :asc)
              .limit(MAX_ACCOUNTS_PER_NIGHT)
  end

  def self.get_current_batch(machine)
    key = "warmup_current_batch_#{machine}"
    batch = Rails.cache.read(key)

    if batch.nil?
      accounts_count = Account.warmup_accounts_for_machine(machine).count
      total_batches = (accounts_count.to_f / MAX_ACCOUNTS_PER_NIGHT).ceil
      total_batches = [total_batches, 1].max

      Account.distribute_warmup_batches(machine, MAX_ACCOUNTS_PER_NIGHT)
      batch = 1
      Rails.cache.write(key, batch, expires_in: 30.days)
    end

    batch
  end

  def self.advance_batch(machine)
    key = "warmup_current_batch_#{machine}"
    current_batch = Rails.cache.read(key) || 1

    accounts_count = Account.warmup_accounts_for_machine(machine).count
    total_batches = (accounts_count.to_f / MAX_ACCOUNTS_PER_NIGHT).ceil
    total_batches = [total_batches, 1].max

    next_batch = current_batch >= total_batches ? 1 : current_batch + 1
    Rails.cache.write(key, next_batch, expires_in: 30.days)
    Rails.logger.info "[WarmupScheduler] 批次已推进到: #{next_batch}/#{total_batches}"
  end

  def self.execute_warmup_for_account(account, machine)
    return if account.browser.nil?

    Rails.logger.info "[WarmupScheduler] 开始养号: #{account.account_name} (#{account.platform})"

    operations = generate_operations(account.platform)
    Rails.logger.info "[WarmupScheduler] 生成操作: #{operations.map { |o| o[:type] }.join(', ')}"

    warmup_task = WarmupTask.create!(
      account: account,
      browser: account.browser,
      platform: account.platform,
      operations: operations.to_json,
      status: :executing,
      machine: machine.to_s
    )

    begin
      endpoint = PLATFORM_ENDPOINTS[account.platform.to_sym]
      unless endpoint
        raise "平台 #{account.platform} 未配置养号接口"
      end

      request_data = build_request_data(account, operations)
      response = send_warmup_request(endpoint, request_data)

      if response['type'] == 'success'
        Rails.logger.info "[WarmupScheduler] 养号成功: #{account.account_name}"
        warmup_task.update!(status: :success, executed_at: Time.current)
        account.update!(last_warmup_at: Time.current, warmup_status: 'success')
      else
        error_msg = response['error_info'] || '养号失败'
        Rails.logger.error "[WarmupScheduler] 养号失败: #{account.account_name} - #{error_msg}"
        warmup_task.update!(status: :failed, error_msg: error_msg, executed_at: Time.current)
        account.update!(warmup_status: 'failed')
      end
    rescue => e
      Rails.logger.error "[WarmupScheduler] 养号异常: #{account.account_name} - #{e.message}"
      warmup_task.update!(status: :failed, error_msg: e.message, executed_at: Time.current)
      account.update!(warmup_status: 'failed')
    end
  end

  def self.generate_operations(platform)
    operation_list = []

    num_browses = rand(5..12)
    num_browses.times { operation_list << { type: 'browse', duration: rand(8..20) } }

    num_likes = rand(2..5)
    num_likes.times { operation_list << { type: 'like' } }

    if rand(0..1) == 1
      num_follows = rand(1..3)
      num_follows.times { operation_list << { type: 'follow' } }
    end

    if rand(0..2) == 1
      operation_list << { type: 'comment', content: generate_comment }
    end

    if rand(0..2) == 1 && ['twitter', 'facebook'].include?(platform.to_s)
      operation_list << { type: 'share' }
    end

    operation_list.shuffle
  end

  def self.generate_comment
    comments = [
      "Great content!",
      "Thanks for sharing!",
      "Interesting perspective!",
      "Love this!",
      "Good job!",
      "Nice post!",
      "Awesome!",
      "Thanks!",
      "Perfect!",
      "Wow!",
      "Interesting!",
      "Great!",
      "Thanks for the info!",
      "Nice!",
      "Cool!"
    ]
    comments.sample
  end

  def self.build_request_data(account, operations)
    {
      profile_name: account.browser.profile_name,
      platform: account.platform,
      operations: operations
    }
  end

  def self.send_warmup_request(endpoint, request_data)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = TIMEOUT_SECONDS
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request.body = request_data.to_json

    response = http.request(request)
    body = response.body

    begin
      JSON.parse(body)
    rescue JSON::ParserError
      { type: 'error', error_info: "响应解析失败: #{body}" }
    end
  end

  def self.time_window_exceeded?
    return false unless @@start_time

    elapsed_hours = (Time.current - @@start_time) / 3600
    elapsed_hours >= TIME_WINDOW_HOURS
  end
end