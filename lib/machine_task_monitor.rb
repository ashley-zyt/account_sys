# 运营机器任务监控 —— 实时查询各机器端任务接口
#
#   聚合看板  GET /tasks/summary   → fetch_all / rows
#   明细列表  GET /tasks           → fetch_tasks（支持 status/type/profile_name/batch/ref_prefix/limit）
#   单任务详情 GET /tasks/{id}     → fetch_task
#
# 为什么实时查而不是落库：
#   机器端任务记录是内存态、天然实时；落库需要在下发链路上为每类任务加登记
#   （采集一天几百条，会把 browser_task_records 撑爆），且机器端重启后本就要靠
#   兜底对账。这里只做「读」，不改任何任务状态，纯监控，随时可下线。
#
# 口径：默认只统计「account_sys 下发的任务」—— 用 ref 前缀过滤；
#       外部系统直接调用机器端产生的任务 ref 为空，会被自然排除。
class MachineTaskMonitor
  # account_sys 下发各类任务时使用的 ref 前缀（与下发代码保持一致）
  #   采集     lib/util.rb#fetch_account_post_data            → "Account:#{account.id}"
  #   养号     lib/warmup_scheduler.rb / lib/execute_worker.rb → "WarmupTask:#{id}"
  #   发私信   → "kol_message:#{id}"
  #   查回复   → "kol_contact:#{id}"
  #   发布     → "<TaskModel>:<id>"（如 MoveTask:123 / OperationTask:123，模型名即前缀）
  OWN_REF_PREFIXES = ['Account:', 'WarmupTask:', 'kol_message:', 'kol_contact:'].freeze

  # 发布类任务的 ref 前缀（模型名 + 冒号），由工作模式注册表动态生成，
  # 保证新增发布模型时自动纳入，不会被 ref_prefix 过滤误伤。
  # 注意：ref_prefix 是全局过滤（对 type 参数里的所有类型都生效），
  # 所以发布类也必须列进来，否则「type 里指定了发布类型、但 ref 前缀不匹配」会被机器端排除，
  # 导致监控页发布类永远显示 0。
  def self.publish_ref_prefixes
    WorkMode.resource_modes.map { |m| "#{m.task_model}:" }
  end

  TRACKED_TYPES = %w[
    fetch nurture send_message check_reply
    facebook_publish twitter_publish youtube_publish tiktok_publish instagram_publish
  ].freeze

  # 只关心「非发布」类时的类型集合（发布类另有浏览器任务页可看）
  NON_PUBLISH_TYPES = %w[fetch nurture send_message check_reply].freeze

  TYPE_LABELS = {
    'fetch'             => '采集',
    'nurture'           => '养号',
    'send_message'      => '发私信',
    'check_reply'       => '查回复',
    'facebook_publish'  => 'Facebook发布',
    'twitter_publish'   => 'X发布',
    'youtube_publish'   => 'YouTube发布',
    'tiktok_publish'    => 'TikTok发布',
    'instagram_publish' => 'Instagram发布'
  }.freeze

  STATUSES = %w[queued running success failed interrupted paused].freeze

  STATUS_LABELS = {
    'queued'      => '排队',
    'running'     => '执行中',
    'success'     => '成功',
    'failed'      => '失败',
    'interrupted' => '已中断',
    'paused'      => '已暂停'
  }.freeze

  # 状态配色 [文字色, 背景色]，页面徽章/数字统一取这里，避免各处硬编码
  STATUS_COLORS = {
    'queued'      => ['#f59e0b', 'rgba(245, 158, 11, 0.15)'],
    'running'     => ['#3b82f6', 'rgba(59, 130, 246, 0.15)'],
    'success'     => ['#22c55e', 'rgba(34, 197, 94, 0.15)'],
    'failed'      => ['#ef4444', 'rgba(239, 68, 68, 0.15)'],
    'interrupted' => ['#94a3b8', 'rgba(148, 163, 184, 0.15)'],
    'paused'      => ['#e879f9', 'rgba(232, 121, 249, 0.15)']
  }.freeze

  SOURCE_LABELS = {
    'account_sys' => 'account_sys',
    'manual'      => '人工/外部'
  }.freeze

  # 明细列表分页（limit 由机器端控制，默认 50、上限 500）
  LIST_DEFAULT_LIMIT = 50
  LIST_MAX_LIMIT     = 500

  # 机器端 TaskRecord 的字段名容错表（按候选键依次取值，取不到返回 nil、视图显示 "—"）。
  # 主键取自《任务查看与操作API.md》3.1「每条 task 的字段」；候选项仅为字段演进兜底。
  # 注意：机器端 TaskRecord **没有** source 字段，来源由 dingtalk_webhook 有无推导（见 task_source）。
  TASK_FIELD_KEYS = {
    id:               %w[task_id id],
    type:             %w[type task_type],
    status:           %w[status],
    profile_name:     %w[profile_name profile],
    ref:              %w[ref],
    batch:            %w[batch batch_id],
    message:          %w[message],
    created_at:       %w[created_at],
    updated_at:       %w[updated_at],
    payload:          %w[payload],
    dingtalk_webhook: %w[dingtalk_webhook]
  }.freeze

  # 单台机器的查询结果。ok=false 时 data 为 nil、error 为原因（机器不可达 / 超时 / HTTP 非 200、404…），
  # code 为 HTTP 状态码（网络异常时为 nil）。
  Result = Struct.new(:machine_ip, :ok, :data, :error, :code, keyword_init: true)

  class << self
    # 所有配置了 machine_ip 的机器（去重、去空白、排序）
    def machine_ips
      Browser.where.not(machine_ip: [nil, ''])
             .distinct.pluck(:machine_ip)
             .compact.map(&:strip).reject(&:empty?).uniq.sort
    end

    # 并行查询多台机器，返回 Result 数组（顺序与传入的 machine_ips 一致）
    # 线程内只发 HTTP、不碰 ActiveRecord，因此不占数据库连接。
    def fetch_all(machine_ips: self.machine_ips, types: TRACKED_TYPES, own_only: true)
      return [] if machine_ips.empty?

      machine_ips.map { |ip| Thread.new { fetch_one(ip, types: types, own_only: own_only) } }
                 .map(&:value)
    end

    # 查询单台机器。任何异常都收敛成 Result(ok: false)，不向上抛。
    def fetch_one(machine_ip, types: TRACKED_TYPES, own_only: true)
      query = { type: types.join(',') }
      if own_only
        # 非发布类固定前缀 + 发布类模型名前缀，全部列出，避免发布类被 ref_prefix 误过滤
        query[:ref_prefix] = (OWN_REF_PREFIXES + publish_ref_prefixes).join(',')
      end

      url = "https://#{machine_ip}/tasks/summary?#{query.to_query}"
      response = RemoteApiClient.get(url, open_timeout: 5, read_timeout: 15)

      unless response.code.to_i == 200
        return Result.new(machine_ip: machine_ip, ok: false, code: response.code.to_i,
                          error: http_error_message(response))
      end

      Result.new(machine_ip: machine_ip, ok: true, code: 200, data: JSON.parse(response.body))
    rescue => e
      Result.new(machine_ip: machine_ip, ok: false, error: e.message)
    end

    # 查询单台机器的任务明细列表（GET /tasks）。
    # 过滤参数与机器端一致，均可逗号分隔多值：status / type / profile_name / batch / ref_prefix。
    # own_only=true 且未显式传 ref_prefix 时，自动拼上本系统下发任务的前缀过滤
    # （注意：与 summary 不同，/tasks 的 total / status_counts 等是「全局口径、不受过滤影响」，
    #   过滤后的真实命中数要看 matched）。
    #
    # @return [Result] ok=true 时 data 为 { total:, matched:, returned:, has_more:, store:,
    #                  status_counts:, source_counts:, type_counts:, type_status_counts:, tasks: [...] }
    def fetch_tasks(machine_ip, types: nil, statuses: nil, profile_name: nil,
                    batch: nil, ref_prefix: nil, limit: LIST_DEFAULT_LIMIT, own_only: true)
      return Result.new(machine_ip: machine_ip, ok: false, error: '未指定机器') if machine_ip.blank?

      types    = split_multi(types)
      statuses = split_multi(statuses)

      query = {}
      query[:type]   = types.join(',')    if types.any?
      query[:status] = statuses.join(',') if statuses.any?
      query[:profile_name] = profile_name.to_s.strip if profile_name.present?
      query[:batch]        = batch.to_s.strip        if batch.present?
      query[:ref_prefix]   = ref_prefix.to_s.strip   if ref_prefix.present?
      if query[:ref_prefix].blank? && own_only
        query[:ref_prefix] = (OWN_REF_PREFIXES + publish_ref_prefixes).join(',')
      end
      query[:limit] = normalize_limit(limit)

      url = "https://#{machine_ip}/tasks?#{query.to_query}"
      response = RemoteApiClient.get(url, open_timeout: 5, read_timeout: 20)

      unless response.code.to_i == 200
        return Result.new(machine_ip: machine_ip, ok: false, code: response.code.to_i,
                          error: http_error_message(response))
      end

      Result.new(machine_ip: machine_ip, ok: true, code: 200, data: JSON.parse(response.body))
    rescue => e
      Result.new(machine_ip: machine_ip, ok: false, error: e.message)
    end

    # 查询机器端单个任务详情（GET /tasks/{id}）。
    # 机器端也是靠这个接口做超时兜底对账（见 TaskScheduler.fetch_remote_task）。
    # 404 = 记录已超期（保留 30 天）或被 /tasks/clear 清掉；**服务重启不会 404**（已落 SQLite）。
    # @return [Result] ok=true 时 data 为完整 TaskRecord 原始 Hash
    def fetch_task(machine_ip, task_id)
      return Result.new(machine_ip: machine_ip, ok: false, error: '未指定机器')   if machine_ip.blank?
      return Result.new(machine_ip: machine_ip, ok: false, error: '未指定任务ID') if task_id.blank?

      url = "https://#{machine_ip}/tasks/#{CGI.escape(task_id.to_s)}"
      response = RemoteApiClient.get(url, open_timeout: 10, read_timeout: 20)

      unless response.code.to_i == 200
        return Result.new(machine_ip: machine_ip, ok: false, code: response.code.to_i,
                          error: http_error_message(response))
      end

      Result.new(machine_ip: machine_ip, ok: true, code: 200, data: JSON.parse(response.body))
    rescue => e
      Result.new(machine_ip: machine_ip, ok: false, error: e.message)
    end

    # 机器端错误响应统一格式：{"type":"error","error_info":"..."}
    # 优先取 error_info（比原始 JSON 片段可读），取不到再回退 HTTP 码 + body 片段
    def http_error_message(response)
      info = (JSON.parse(response.body.to_s)['error_info'] rescue nil)
      return "HTTP #{response.code}：#{info}" if info.present?
      "HTTP #{response.code}: #{response.body.to_s[0, 200]}"
    end

    # 逗号分隔 / 数组 统一拆成去空数组（过滤参数既可能来自多选数组，也可能来自手填字符串）
    def split_multi(value)
      Array(value).flat_map { |v| v.to_s.split(',') }.map(&:strip).reject(&:empty?)
    end

    # limit 收敛到 [1, 500]，非法/未传回落到默认 50
    def normalize_limit(value)
      n = value.to_i
      n = LIST_DEFAULT_LIMIT if n <= 0
      [n, LIST_MAX_LIMIT].min
    end

    # 状态配色（取不到时用中性灰）
    def status_color(status)
      STATUS_COLORS[status.to_s] || ['#94a3b8', 'rgba(148, 163, 184, 0.15)']
    end

    # 从机器端任务 Hash 里按候选键取值（值可能为 nil / 空串，都算取不到）
    def pick_field(task, keys)
      keys.each do |k|
        v = task[k]
        next if v.nil?
        return v if !v.respond_to?(:empty?) || !v.empty?
      end
      nil
    end

    # 来源推导：机器端 TaskRecord **没有** source 字段，统计里的 source_counts 依据是
    # 「是否带 dingtalk_webhook」—— 有 = 人工/外部直接调 API，无 = account_sys 下发。
    def task_source(task)
      pick_field(task.to_h, TASK_FIELD_KEYS[:dingtalk_webhook]).present? ? 'manual' : 'account_sys'
    end

    # 把机器端单条 TaskRecord 整理成视图用的统一结构（字段名做容错，另带 raw 原始 Hash）
    def normalize_task(task)
      task = task.to_h
      norm = {}
      TASK_FIELD_KEYS.each { |field, keys| norm[field] = pick_field(task, keys) }
      norm[:type_label]   = TYPE_LABELS[norm[:type].to_s] || norm[:type].to_s
      norm[:status_label] = STATUS_LABELS[norm[:status].to_s] || norm[:status].to_s
      norm[:source]       = task_source(task)
      norm[:source_label] = SOURCE_LABELS[norm[:source]]
      norm[:raw]          = task
      norm
    end

    # 明细列表响应 → 统一结构数组
    def normalize_tasks(data)
      Array(data['tasks']).map { |t| normalize_task(t) }
    end

    # 便捷：把某台机器的 summary 响应整理成「类型小计 + 堆积落点 + 批次进度」，供视图直接用
    # @return [Hash] { types: [...], backlog: [...], batches: [...], batch_total:, unbatched: }
    def rows(data)
      ts = data['type_status_counts'] || {}
      types = TRACKED_TYPES.map do |type|
        row = ts[type] || {}
        {
          type:        type,
          label:       TYPE_LABELS[type] || type,
          queued:      row['queued'].to_i,
          running:     row['running'].to_i,
          success:     row['success'].to_i,
          failed:      row['failed'].to_i,
          interrupted: row['interrupted'].to_i,
          paused:      row['paused'].to_i,
          total:       row.values.sum(&:to_i)
        }
      end.reject { |r| r[:total].zero? }

      backlog = (data['profiles'] || []).select { |p| p['queued'].to_i > 0 || p['running'].to_i > 0 }

      batches = (data['batches'] || []).map do |b|
        {
          batch:       b['batch'],
          queued:      b['queued'].to_i,
          running:     b['running'].to_i,
          success:     b['success'].to_i,
          failed:      b['failed'].to_i,
          interrupted: b['interrupted'].to_i,
          paused:      b['paused'].to_i,
          total:       b['total'].to_i,
          pending:     b['pending'].to_i,
          # done 只代表「没有待执行任务」，仍可能含 failed/interrupted
          done:        b['done'] == true,
          first_seen:  b['first_seen'],
          last_update: b['last_update'],
          duration_seconds: b['duration_seconds'].to_i
        }
      end

      {
        types:       types,
        backlog:     backlog,
        batches:     batches,
        batch_total: data['batch_total'].to_i,
        unbatched:   data['unbatched'].to_i
      }
    end
  end
end
