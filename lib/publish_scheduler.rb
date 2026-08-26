# 发布调度器
# 用于执行人工运营账号的发布操作
# 支持 OperationTask / GrokTask / HeygenTask / JianyingTask 多种任务类型
#
# 调度模型：
#   - 按浏览器所属运营机器 IP（browser.machine_ip）分组
#   - 每台机器一个 Thread 并行执行，互不影响
#   - 同一台机器内的任务顺序执行（同一台机器同时只能操作一个 profile，避免 lock）
#   - 端点动态生成：http://<browser.machine_ip>:8080/<platform>/publish（端口固定 8080）
class PublishScheduler

  # 运营机器发布服务固定端口
  PUBLISH_PORT = 8080

  TIMEOUT_SECONDS = 600
  # 同一机器内任务之间的间隔（秒），避免连续打开同一 profile 导致 lock
  TASK_INTERVAL = 40

  # 统一入口：按 browser.machine_ip 分组，多台机器并行运行
  # @param platform [String, nil] 限定平台，nil 表示所有平台
  def self.run(platform: nil)
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'publishscheduler_run.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    machine_ips = target_machine_ips(platform: platform)
    Rails.logger.info "[PublishScheduler] 平台 #{platform || '全部'} 发现 #{machine_ips.size} 台运营机器: #{machine_ips.join(', ')}"

    # 提示存在未设置 machine_ip 的待发布任务浏览器
    orphan_count = orphan_browser_count(platform: platform)
    if orphan_count > 0
      Rails.logger.warn "[PublishScheduler] 有 #{orphan_count} 个待发布任务的浏览器未设置 machine_ip，本轮跳过，请在浏览器页面补全机器IP"
    end

    return if machine_ips.empty?

    # 每台机器并行执行
    threads = machine_ips.map do |ip|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          run_for_machine(ip, platform: platform)
        end
      end
    end
    threads.each(&:join)

    # 首轮发布完成，重新分配资源并重试（保持原有逻辑：仅指定平台时重试）
    if platform.present?
      Rails.logger.info "[PublishScheduler] 平台 #{platform} 首轮发布完成，开始重试流程"
      TaskScheduler.assign_resources(platform: platform)

      # 重试时仍按机器并行
      retry_threads = machine_ips.map do |ip|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            run_for_machine(ip, platform: platform)
          end
        end
      end
      retry_threads.each(&:join)
      Rails.logger.info "[PublishScheduler] 平台 #{platform} 重试流程完成"
    end

    Rails.logger.info "[PublishScheduler] 所有机器发布任务执行完成"
  end

  # 针对单台机器顺序执行其待发布任务
  # @param machine_ip [String] 运营机器 IP
  # @param platform [String, nil] 限定平台
  def self.run_for_machine(machine_ip, platform: nil)
    loop do
      task = execute_next_task_for_machine(machine_ip, platform: platform)
      break unless task
    end
  end

  # 执行单台机器的下一个任务（顺序执行，避免 profile lock）
  # @return [Object, false] 返回执行的任务对象；无任务时返回 false
  def self.execute_next_task_for_machine(machine_ip, platform: nil)
    tasks = fetch_tasks_for_machine(machine_ip, platform: platform)
    return false if tasks.empty?

    last_browser_id = get_last_browser_id
    task = select_next_task(tasks, last_browser_id)
    return false unless task

    task_type = task_type_name(task)

    # 事务锁定任务，避免被其他机器或线程重复执行
    ActiveRecord::Base.transaction do
      task.lock!
      return false unless task.status == 'waiting_publish'
      task.update!(status: :executing, start_at: Time.current)
    end

    execute_task(task, task_type, machine_ip)
    sleep(TASK_INTERVAL)
    task
  end

  # === 旧入口兼容（保留以避免外部调用断裂） ===
  # 单线程顺序执行下一个任务，按机器 IP 自动路由端点
  def self.execute_next_task(platform: nil)
    tasks = fetch_all_tasks(platform: platform)
    return false if tasks.empty?

    last_browser_id = get_last_browser_id
    task = select_next_task(tasks, last_browser_id)
    return false unless task

    task_type = task_type_name(task)

    ActiveRecord::Base.transaction do
      task.lock!
      return false unless task.status == 'waiting_publish'
      task.update!(status: :executing, start_at: Time.current)
    end

    # 端点由该任务浏览器的 machine_ip 决定
    machine_ip = task.browser&.machine_ip
    execute_task(task, task_type, machine_ip)
    sleep(TASK_INTERVAL)
    true
  end

  # === 数据获取 ===

  def self.fetch_all_tasks(platform: nil)
    operation_tasks = OperationTask.where(status: :waiting_publish)
                                   .where("account_id IS NOT NULL")
                                   .includes(:browser)

    grok_tasks = GrokTask.where(status: :waiting_publish)
                         .where("account_id IS NOT NULL")
                         .includes(:browser)

    heygen_tasks = HeygenTask.where(status: :waiting_publish)
                             .where("account_id IS NOT NULL")
                             .includes(:browser)

    jianying_tasks = JianyingTask.where(status: :waiting_publish)
                               .where("account_id IS NOT NULL")
                               .includes(:browser)

    # 搬运任务：视频搬运模式的资源队列，发布时与运营/Grok/剪映任务一并执行
    move_tasks = MoveTask.where(status: :waiting_publish)
                         .where("account_id IS NOT NULL")
                         .includes(:browser)

    huasheng_tasks = HuashengTask.where(status: :waiting_publish)
                               .where("account_id IS NOT NULL")
                               .includes(:browser)
    notebooklm_tasks = NotebooklmTask.where(status: :waiting_publish)
                                  .where("account_id IS NOT NULL")
                                  .includes(:browser)



    tasks = operation_tasks.to_a + grok_tasks.to_a + heygen_tasks.to_a + jianying_tasks.to_a + move_tasks.to_a + huasheng_tasks.to_a + notebooklm_tasks.to_a
    tasks = tasks.select { |t| t.platform == platform } if platform.present?
    tasks
  end

  # 获取指定机器下所有待发布任务
  def self.fetch_tasks_for_machine(machine_ip, platform: nil)
    fetch_all_tasks(platform: platform).select do |t|
      t.browser&.machine_ip == machine_ip
    end
  end

  # 当前需要参与发布的所有运营机器 IP
  def self.target_machine_ips(platform: nil)
    browser_ids = fetch_all_tasks(platform: platform).map(&:browser_id).compact.uniq
    Browser.where(id: browser_ids)
           .where.not(machine_ip: [nil, ""])
           .distinct
           .pluck(:machine_ip)
  end

  # 待发布任务中浏览器未设置 machine_ip 的数量（用于日志提醒）
  def self.orphan_browser_count(platform: nil)
    tasks = fetch_all_tasks(platform: platform)
    tasks.count { |t| t.browser&.machine_ip.blank? }
  end

  # === 任务选择 ===

  def self.select_next_task(tasks, last_browser_id)
    # 避免连续两次选择同一浏览器（防止同一 profile 被反复打开导致 lock）
    tasks_without_last_browser = tasks.reject { |t| t.browser_id == last_browser_id }

    if tasks_without_last_browser.any?
      tasks_without_last_browser.min_by { |t| t.created_at }
    else
      tasks.min_by { |t| t.created_at }
    end
  end

  def self.get_last_browser_id
    last_task_log = TaskLog.where("browser_id IS NOT NULL")
                          .order(id: :desc)
                          .first
    last_task_log&.browser_id
  end

  def self.save_last_browser_id(browser_id)
  end

  # === 任务执行 ===

  def self.execute_task(task, task_type, machine_ip)
    return if task.account.nil? || task.browser.nil?

    # 端点由浏览器所属运营机器决定；端口固定 8080
    unless machine_ip.present?
      error_msg = "浏览器 #{task.browser.profile_name} 未设置运营机器 IP，无法发布"
      Rails.logger.error "[PublishScheduler] 任务 #{task_type}:#{task.id} #{error_msg}"
      handle_error(task, error_msg)
      return
    end

    endpoint = "http://#{machine_ip}:#{PUBLISH_PORT}/#{task.platform}/publish"

    Rails.logger.info "[PublishScheduler] 开始执行任务 #{task_type}:#{task.id} - #{task.title} (浏览器: #{task.browser.profile_name}, 机器: #{machine_ip}) → #{endpoint}"

    begin
      request_data = build_request_data(task)
      response = send_publish_request(endpoint, request_data)
      handle_response(task, response)
    rescue Net::ReadTimeout
      Rails.logger.error "[PublishScheduler] 任务 #{task_type}:#{task.id} 机器 #{machine_ip} 单任务超出十分钟异常结束"
      handle_error(task, "单任务超出十分钟异常结束")
    rescue => e
      Rails.logger.error "[PublishScheduler] 任务 #{task_type}:#{task.id} 机器 #{machine_ip} 执行异常: #{e.message}"
      handle_error(task, "执行异常: #{e.message}")
    end
  end

  def self.task_type_name(task)
    if task.is_a?(OperationTask)
      'operation'
    elsif task.is_a?(GrokTask)
      'grok'
    elsif task.is_a?(HeygenTask)
      'heygen'
    elsif task.is_a?(JianyingTask)
      'jianying'
    elsif task.is_a?(MoveTask)
      'move'
    elsif task.is_a?(HuashengTask)
      'huasheng'
    elsif task.is_a?(NotebooklmTask)
      'notebooklm'
    else
      'operation'
    end
  end

  def self.build_request_data(task)
    # 运营/剪映/搬运/花生 任务均使用 oss_url 作为视频地址；Grok/Heygen 使用 video_url
    video_url = if task.is_a?(OperationTask) || task.is_a?(JianyingTask) || task.is_a?(MoveTask) || task.is_a?(HuashengTask) || task.is_a?(NotebooklmTask)
                  task.oss_url
                else
                  task.video_url
                end
    # MoveTask 没有 description 字段，搬运模式发布不需要描述
    description = task.respond_to?(:description) ? task.description.to_s : ""
    {
      profile_name: ensure_utf8(task.browser.profile_name),
      title: ensure_utf8(task.title),
      video_oss_url: ensure_utf8(video_url),
      description: ensure_utf8(description)
    }
  end

  def self.send_publish_request(endpoint, request_data)
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = TIMEOUT_SECONDS
    http.open_timeout = 30

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request.body = request_data.to_json

    response = http.request(request)
    body = ensure_utf8(response.body)

    begin
      JSON.parse(body)
    rescue JSON::ParserError
      { type: 'error', error_info: "响应解析失败: #{body}" }
    end
  end

  def self.handle_response(task, response)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    if response['type'] == 'success'
      Rails.logger.info "[PublishScheduler] 任务 #{task.id} 发布成功"
      TaskReportHelper.update_task_status(task, 'success')
      TaskReportHelper.create_task_log(task, 'success', snapshot_account_id, snapshot_browser_id)
    else
      error_msg = response['error_info'] || '发布失败'
      Rails.logger.error "[PublishScheduler] 任务 #{task.id} 发布失败: #{error_msg}"
      TaskReportHelper.update_task_status(task, 'error', error_msg)
      TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, error_msg)
    end
  end

  def self.handle_error(task, error_msg)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    TaskReportHelper.update_task_status(task, 'error', error_msg)
    TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, error_msg)
  end

  def self.ensure_utf8(str)
    return str unless str.is_a?(String)
    str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  end

end
