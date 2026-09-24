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

    # 首轮：全局 worker 池并行发布（受占用中心「每机器≤4 + 同浏览器互斥」约束）
    tasks = fetch_all_tasks(platform: platform)
    run_tasks_with_pool(tasks, machine_count: machine_ips.size)

    # 首轮发布完成，重新分配资源并重试（保持原有逻辑：仅指定平台时重试）
    if platform.present?
      Rails.logger.info "[PublishScheduler] 平台 #{platform} 首轮发布完成，开始重试流程"
      TaskScheduler.assign_resources(platform: platform)

      retry_tasks = fetch_all_tasks(platform: platform)
      run_tasks_with_pool(retry_tasks, machine_count: machine_ips.size)
      Rails.logger.info "[PublishScheduler] 平台 #{platform} 重试流程完成"
    end

    Rails.logger.info "[PublishScheduler] 所有机器发布任务执行完成"
  end

  # 用 worker 池并行执行一批待发布任务：非阻塞占用，忙的放回队尾重试，谁空闲谁先走。
  # 并发受占用中心约束（同浏览器互斥 + 每机器≤4），worker 数再受连接池上限约束。
  # @param tasks [Array] 待发布任务列表
  # @param machine_count [Integer] 参与发布的机器数（用于计算 worker 池上限）
  def self.run_tasks_with_pool(tasks, machine_count: nil)
    return if tasks.empty?

    machine_count ||= tasks.map { |t| t.browser&.machine_ip }.compact.uniq.size
    db_pool_size = ActiveRecord::Base.connection_pool.size
    # 并发已交给机器端（async 模式下机器端自己排队），worker 池只负责并行「下发指令」，
    # 不再受「每机器 N 浏览器」约束，仅受连接池大小限制。
    pool_size = [tasks.size, db_pool_size].min
    pool_size = 1 if pool_size <= 0

    Rails.logger.info "[PublishScheduler] 本轮待发布任务 #{tasks.size} 个，worker 池=#{pool_size}（机器=#{machine_count}，连接池=#{db_pool_size}）"

    # 释放主线程占用的连接，让 worker 能拿满整个连接池
    ActiveRecord::Base.connection_pool.release_connection

    mutex     = Mutex.new
    queue     = tasks.dup
    remaining = tasks.size
    worker_id = 0

    workers = Array.new(pool_size) do
      wid = mutex.synchronize { worker_id += 1 }
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          loop do
            task = mutex.synchronize { queue.shift }
            unless task
              break if mutex.synchronize { remaining <= 0 }
              sleep(10)
              next
            end

            if attempt_task(task) == :busy
              mutex.synchronize { queue << task }
              sleep(10)
            else
              mutex.synchronize { remaining -= 1 }
            end
          end
        end
      end
    end
    workers.each(&:join)
  end

  # 尝试执行单个待发布任务（非阻塞）。
  # @return [Symbol] :done 已执行/跳过（无需重试）；:busy 浏览器忙或机器满（需放回重试）
  def self.attempt_task(task)
    # postforme 渠道：不依赖浏览器/机器端，走第三方 API 发布
    return attempt_postforme_task(task) if task.account&.publish_channel == 'postforme'

    browser = task.browser
    return :done if browser.nil? || browser.machine_ip.blank?

    today_range = Date.today.beginning_of_day..Date.today.end_of_day

    # 防同账号多次发布：该账号今天已有成功发布记录，这条多余的 waiting_publish 任务
    # 重置回 pending（释放资源），不再发布
    if task.account_id.present? &&
       task.class.exists?(account_id: task.account_id, status: :success, actual_publish_time: today_range)
      Rails.logger.info "[PublishScheduler] 任务 #{task_type_name(task)}##{task.id} 对应账号 ##{task.account_id} 今天已发布成功，重置为 pending 跳过"
      # 归属即将从任务上清空，先标进 TaskAssignment 留档（只标记、不删）
      TaskAssignment.release!(task.task_uuid, '账号今日已发布成功，释放待重新分配')
      task.update!(status: :pending, account_id: nil, browser_id: nil, start_at: nil)
      return :done
    end

    # 并发/占用已完全交给机器端（async 模式下机器端自己排队 + profile 锁），
    # account_sys 侧不再前置占用控制，直接锁定任务并下发异步指令。
    task_type = task_type_name(task)

    # 事务锁定任务，避免重复执行；抢不到则放弃本轮
    executed = false
    ActiveRecord::Base.transaction do
      task.lock!
      if task.status == 'waiting_publish'
        task.update!(status: :executing, start_at: Time.current)
        executed = true
      end
    end
    return :done unless executed

    execute_task(task, task_type, browser.machine_ip)
    :done
  end

  # postforme 渠道任务执行：锁定任务 → 调 postforme 提交发布（异步，结果由轮询回写）。
  # 提交成功拿 post_id 后任务保持 executing，等 PostformeStatusPoller 轮询到终态回写；
  # 提交失败则走 handle_error 重置任务。
  def self.attempt_postforme_task(task)
    today_range = Date.today.beginning_of_day..Date.today.end_of_day

    # 防同账号多次发布：该账号今天已有成功发布记录，释放这条多余的 waiting_publish 任务
    if task.account_id.present? &&
       task.class.exists?(account_id: task.account_id, status: :success, actual_publish_time: today_range)
      Rails.logger.info "[PublishScheduler] 任务 #{task_type_name(task)}##{task.id} 对应账号 ##{task.account_id} 今天已发布成功，重置为 pending 跳过"
      TaskAssignment.release!(task.task_uuid, '账号今日已发布成功，释放待重新分配')
      task.update!(status: :pending, account_id: nil, browser_id: nil, start_at: nil)
      return :done
    end

    # 事务锁定任务，避免重复执行；抢不到则放弃本轮
    executed = false
    ActiveRecord::Base.transaction do
      task.lock!
      if task.status == 'waiting_publish'
        task.update!(status: :executing, start_at: Time.current)
        executed = true
      end
    end
    return :done unless executed

    result = PostformePublisher.publish(task)
    if result[:success]
      Rails.logger.info "[PublishScheduler] postforme 任务 #{task.class.name}##{task.id} 已提交：#{result[:message]}"
    else
      Rails.logger.error "[PublishScheduler] postforme 任务 #{task.class.name}##{task.id} 提交失败：#{result[:message]}"
      handle_error(task, result[:message])
    end
    :done
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
    tasks = WorkMode.publishable_modes.flat_map do |mode|
      mode.task_model_class.where(status: :waiting_publish)
                           .where("account_id IS NOT NULL")
                           .includes(:browser)
                           .to_a
    end
    tasks = tasks.select { |t| t.platform == platform } if platform.present?
    tasks
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

    endpoint = "https://#{machine_ip}/#{task.platform}/publish"

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

  # 手动立即执行单个任务（供后台「立即执行」按钮调用）
  # 校验 waiting_publish → 事务锁 + 改 executing → 发布
  # @param task [Object] 任一工作模式的任务实例
  # @return [Boolean] 是否成功触发执行
  def self.execute_single_task(task)
    return false if task.nil?
    return false unless task.respond_to?(:waiting_publish?) && task.waiting_publish?
    return false if task.browser.nil? || task.browser.machine_ip.blank?

    ActiveRecord::Base.transaction do
      task.lock!
      return false unless task.waiting_publish?
      task.update!(status: :executing, start_at: Time.current)
    end

    execute_task(task, task_type_name(task), task.browser.machine_ip)
    true
  end

  def self.task_type_name(task)
    WorkMode.for_model(task.class)&.type_name || 'operation'
  end

  # 给指定账号立即发布一条资源（手动触发，绕过全局调度，直接指定资源）
  #
  # 逻辑：
  #   1. 根据账号工作模式（work_type）确定其资源队列 Model
  #   2. 优先取该账号已分配（waiting_publish）的任务；否则取一条 pending 资源
  #      （按平台+主题匹配，规则同 TaskScheduler.assign_resources）直接指派给该账号
  #   3. 调用 execute_single_task 立即发布（含任务日志、状态流转）
  #
  # @param account_id [Integer] 账号 ID
  # @param task_id    [Integer, nil] 可选：直接指定某条资源的 ID（须属于该账号工作模式的队列）
  # @return [Hash] { success:, message:, task:, task_type: }
  def self.publish_for_account(account_id, task_id: nil)
    account = Account.find_by(id: account_id)
    return { success: false, message: "账号不存在或已删除（id=#{account_id}）" } unless account

    task_model = account.task_model_for_work_type
    return { success: false, message: "账号「#{account.account_name}」工作模式=#{account.work_type}，无资源队列，无法发布" } unless task_model

    if account.browser.blank?
      return { success: false, message: "账号「#{account.account_name}」未绑定指纹浏览器，无法发布" }
    end
    if account.browser.machine_ip.blank?
      return { success: false, message: "账号「#{account.account_name}」绑定的浏览器未设置 machine_ip，无法发布" }
    end

    # 说明：本方法主要用于测试发布功能，不做「当天已发布过」校验（每天可多次触发）

    task = resolve_task(account, task_model, task_id)
    return { success: false, message: "账号「#{account.account_name}」无可用资源（waiting_publish/pending 均无匹配平台+主题的记录）" } unless task

    # 资源必须处于待发布状态才能走正常发布流程（success/failed/executing 一律拒绝）
    unless task.waiting_publish?
      return { success: false, message: "资源 ##{task.id} 当前状态=#{task.status}，非待发布（waiting_publish），无法执行", task: task }
    end

    unless execute_single_task(task)
      return { success: false, message: "资源 ##{task.id} 发布触发失败（状态仍为 waiting_publish）", task: task }
    end

    {
      success: true,
      message: "已为账号「#{account.account_name}」发布资源：#{task_model}##{task.id}（主题=#{task.theme}）",
      task: task,
      task_type: task_type_name(task)
    }
  end

  # 解析要发布的资源：
  #   - 指定 task_id 时：校验属于该工作模式队列，pending 则指派给账号，已归属其它账号则报错
  #   - 未指定时：优先取该账号已分配的 waiting_publish，否则取 pending 并指派
  def self.resolve_task(account, task_model, task_id)
    if task_id.present?
      task = task_model.find_by(id: task_id)
      return nil unless task

      if task.pending?
        assign_to_account!(task, account)
      elsif task.account_id != account.id
        Rails.logger.warn "[PublishScheduler] 资源 ##{task.id} 已指派给账号 #{task.account_id}，非目标账号 #{account.id}"
        return nil
      end
      return task
    end

    task = task_model.where(status: :waiting_publish, account_id: account.id).order(:created_at).first
    return task if task

    pending_task = task_model.where(status: :pending, platform: account.platform, theme: account.theme).order(:created_at).first
    return nil unless pending_task

    assign_to_account!(pending_task, account)
    pending_task
  end

  # 把一条 pending 资源指派给账号（事务+行锁，防止并发重复分配）
  def self.assign_to_account!(task, account)
    ActiveRecord::Base.transaction do
      task.lock!
      return unless task.pending?
      task.update!(account_id: account.id, browser_id: account.browser_id, status: :waiting_publish)
      # 发活那一刻固化归属（释放时只标记、不删除，供迟到的回调归档日志）
      TaskAssignment.record!(task)
    end
  end

  def self.build_request_data(task)
    # 视频地址字段由注册表决定（oss_url / video_url）
    mode = WorkMode.for_model(task.class)
    video_url = (mode && mode.video_field.present?) ? task.public_send(mode.video_field) : nil
    # 部分任务（如 MoveTask）没有 description 字段，发布不需要描述
    description = task.respond_to?(:description) ? task.description.to_s : ""
    {
      profile_name: ensure_utf8(task.browser.profile_name),
      title: ensure_utf8(task.title),
      video_oss_url: ensure_utf8(video_url),
      description: ensure_utf8(description),
      # 异步模式：机器端立即返回 accepted+task_id，后台执行，完成后回调 /api/v1/browser_tasks/result
      async: true,
      # 业务透传标识：回调时机器端原样带回，用于精确关联到本任务
      ref: "#{task.class.name}:#{task.id}"
    }
  end

  def self.send_publish_request(endpoint, request_data)
    response = RemoteApiClient.post(endpoint, request_data, read_timeout: TIMEOUT_SECONDS)
    body = ensure_utf8(response.body)

    begin
      JSON.parse(body)
    rescue JSON::ParserError
      { type: 'error', error_info: "响应解析失败: #{body}" }
    end
  end

  def self.handle_response(task, response)
    # 异步受理：机器端已接收任务，后台执行中，等 /api/v1/browser_tasks/result 回调后再更新状态
    if response['type'] == 'accepted'
      BrowserTaskRecord.track!(
        machine_task_id: response['task_id'],
        ref: "#{task.class.name}:#{task.id}",
        task_type: "#{task.platform}_publish",
        profile_name: task.browser&.profile_name,
        machine_ip: task.browser&.machine_ip
      )
      Rails.logger.info "[PublishScheduler] 任务 #{task.id} 已受理（异步），task_id=#{response['task_id']}，等待回调"
      return
    end

    # 同步兜底（机器端未启用 async 时）：按原逻辑立即更新状态
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

  # 确保字符串是干净的 UTF-8：
  #   - 已经是合法 UTF-8 就原样返回（避免把日文等多字节字符按二进制转坏成空）
  #   - ASCII-8BIT/binary（如 Net::HTTP 响应体）先按 UTF-8 重打标签再校验
  #   - 其它编码正常转码；非法字节替换为空
  def self.ensure_utf8(str)
    return str unless str.is_a?(String)
    return str if str.encoding == Encoding::UTF_8 && str.valid_encoding?

    s = str.dup
    s.force_encoding(Encoding::UTF_8) if s.encoding == Encoding::ASCII_8BIT
    s.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '')
  end

end
