# 发布调度器
# 用于执行人工运营账号的发布操作
# 支持 OperationTask 和 GrokTask 两种任务类型
class PublishScheduler

  PLATFORM_ENDPOINTS = {
    facebook: 'http://174.139.46.15:8080/facebook/publish',
    twitter: 'http://174.139.46.15:8080/twitter/publish',
    youtube: 'http://174.139.46.15:8080/youtube/publish',
    tiktok: 'http://174.139.46.15:8080/tiktok/publish',
    instagram: 'http://174.139.46.15:8080/instagram/publish'
  }

  TIMEOUT_SECONDS = 600
  TASK_INTERVAL = 40

  def self.run
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'publishscheduler_run.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    loop do
      break unless execute_next_task
    end
  end

  def self.execute_next_task
    tasks = fetch_all_tasks
    return false if tasks.empty?

    last_browser_id = get_last_browser_id

    task = select_next_task(tasks, last_browser_id)
    return false unless task

    task_type = if task.is_a?(OperationTask)
                  'operation'
                elsif task.is_a?(GrokTask)
                  'grok'
                elsif task.is_a?(HeygenTask)
                  'heygen'
                else
                  'operation'
                end

    ActiveRecord::Base.transaction do
      task.lock!
      return false unless task.status == 'waiting_publish'

      task.update!(status: :executing, start_at: Time.current)
    end

    execute_task(task, task_type)
    sleep(TASK_INTERVAL)
    true
  end

  def self.fetch_all_tasks
    operation_tasks = OperationTask.where(status: :waiting_publish)
                                   .where("account_id IS NOT NULL")
                                   .includes(:browser)

    grok_tasks = GrokTask.where(status: :waiting_publish)
                         .where("account_id IS NOT NULL")
                         .includes(:browser)

    heygen_tasks = HeygenTask.where(status: :waiting_publish)
                             .where("account_id IS NOT NULL")
                             .includes(:browser)

    operation_tasks.to_a + grok_tasks.to_a + heygen_tasks.to_a
  end

  def self.select_next_task(tasks, last_browser_id)
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

  def self.execute_task(task, task_type)
    return if task.account.nil? || task.browser.nil?

    Rails.logger.info "[PublishScheduler] 开始执行任务 #{task_type}:#{task.id} - #{task.title} (浏览器: #{task.browser.profile_name})"

    begin
      endpoint = PLATFORM_ENDPOINTS[task.platform.to_sym]
      return unless endpoint

      request_data = build_request_data(task)

      response = send_publish_request(endpoint, request_data)

      handle_response(task, response)

    rescue Net::ReadTimeout
      Rails.logger.error "[PublishScheduler] 任务 #{task_type}:#{task.id} 单任务超出十分钟异常结束"
      handle_error(task, "单任务超出十分钟异常结束")
    rescue => e
      Rails.logger.error "[PublishScheduler] 任务 #{task_type}:#{task.id} 执行异常: #{e.message}"
      handle_error(task, "执行异常: #{e.message}")
    end
  end

  def self.build_request_data(task)
    {
      profile_name: ensure_utf8(task.browser.profile_name),
      title: ensure_utf8(task.title),
      video_oss_url: ensure_utf8(task.is_a?(OperationTask) ? task.oss_url : task.video_url),
      description: ensure_utf8(task.description.to_s)
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
