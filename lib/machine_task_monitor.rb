# 运营机器任务监控 —— 实时聚合查询各机器端 GET /tasks/summary
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

  # 单台机器的查询结果。ok=false 时 data 为 nil、error 为原因（机器不可达 / 超时 / HTTP 非 200）
  Result = Struct.new(:machine_ip, :ok, :data, :error, keyword_init: true)

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
        return Result.new(machine_ip: machine_ip, ok: false,
                          error: "HTTP #{response.code}: #{response.body.to_s[0, 200]}")
      end

      Result.new(machine_ip: machine_ip, ok: true, data: JSON.parse(response.body))
    rescue => e
      Result.new(machine_ip: machine_ip, ok: false, error: e.message)
    end

    # 便捷：把某台机器的响应整理成「按类型的小计 + 堆积落点」，供视图直接用
    # @return [Hash] { types: [{type:, label:, queued:, running:, success:, failed:, total:}], backlog: [...] }
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

      { types: types, backlog: backlog }
    end
  end
end
