# 视频存储清理服务（lib/storage_cleaner.rb，已 autoload）。
#
# 链路一 clean_published_queues —— 成品资源队列清理：
#   覆盖 7 张含 OSS 成品的资源队列表（HeygenTask 除外：视频托管在第三方 CDN）。
#   逐条记录判断：
#     waiting_publish / executing      → 保留（进行中，文件仍需）
#     pending 且主题该平台有正常账号    → 保留（还会发）
#     pending 且无账号（孤儿）          → 删记录
#     failed（终态·资源失效）           → 删记录
#     success                          → 保留记录（历史），文件可释放
#   文件删除用「URL 去重 + 排除仍被引用」：某 URL 只要不再被任何仍需文件的记录引用即可删。
#   特殊：HuashengTask「抖音-视频号」只保留 pending，success/failed 一并删记录 + 删文件。
#
# 链路二 clean_source_videos —— 源视频 raw OSS 清理：
#   MoveVideo.raw_oss_url 是剪映 + 混剪两条线的共同输入。某条线「不再需要源视频」当且仅当：
#   该线状态已 completed（failed_as_done: true 时也含 failed），或该主题在该线的工作模式下
#   已无正常账号（该线不会再消费这条源视频）。两条线都不再需要时才删 raw 文件并置空字段。
#
# 用法（rails runner）：
#   预览： bundle exec rails runner 'StorageCleaner.clean_published_queues'
#   执行： bundle exec rails runner 'StorageCleaner.clean_published_queues(dry_run: false)'
class StorageCleaner
  # 含 OSS 成品的资源队列表（HeygenTask 排除：视频托管在第三方 Heygen CDN，不占 OSS 费用）
  OSS_QUEUE_MODELS = [
    MoveTask, HunjianTask, JianyingTask, OperationTask,
    HuashengTask, NotebooklmTask, GrokTask
  ].freeze

  # HuashengTask 国内「抖音-视频号」合并任务的 platform 值
  DOUYIN_SHIPINHAO_PLATFORM = "抖音-视频号"

  OSS_ENDPOINT = 'https://oss-cn-hangzhou.aliyuncs.com'.freeze

  # 两组 OSS 凭证对应的 bucket：
  #   - ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET（主账号）
  #     → grok-images、grok-videos、jianying-videos、operation-viodes
  #   - ALIYUN_ACCESS_TWO_KEY_ID / ALIYUN_ACCESS_TWO_KEY_SECRET（TWO 账号）
  #     → jianying-rd、huasheng-ld、notebooklm-ld
  # 未列入 TWO_KEY_BUCKETS 的 bucket 一律走主账号凭证。
  TWO_KEY_BUCKETS = %w[jianying-rd huasheng-ld notebooklm-ld].freeze

  # ---------- 链路一：成品资源队列清理 ----------
  def self.clean_published_queues(dry_run: true)
    summary = { records_deleted: 0, files_deleted: 0, files_failed: 0, kept: 0 }
    allowed_cache = {}

    OSS_QUEUE_MODELS.each do |model|
      work_type   = WorkMode.for_model(model).name
      video_field = WorkMode.for_model(model).video_field   # oss_url / video_url

      delete_ids      = []
      needed_urls     = []   # 仍需文件（进行中 / 还会发）
      releasable_urls = []   # 文件可释放（success / failed / 孤儿 pending）

      model.find_each do |t|
        url = t.public_send(video_field).to_s.strip

        # 国内「抖音-视频号」特殊分支：只保留 pending，其余直接删
        if t.is_a?(HuashengTask) && t.platform == DOUYIN_SHIPINHAO_PLATFORM
          if t.status == 'pending'
            needed_urls << url if url.present?
            summary[:kept] += 1
          else
            delete_ids << t.id
            releasable_urls << url if url.present?
          end
          next
        end

        case t.status
        when 'waiting_publish', 'executing'
          needed_urls << url if url.present?
          summary[:kept] += 1
        when 'success'
          releasable_urls << url if url.present?
          summary[:kept] += 1
        when 'failed'
          delete_ids << t.id
          releasable_urls << url if url.present?
        when 'pending'
          allowed = (allowed_cache[[t.theme, work_type]] ||= Account.active_platforms_for(theme: t.theme, work_type: work_type))
          if allowed.include?(t.platform)
            needed_urls << url if url.present?
            summary[:kept] += 1
          else
            delete_ids << t.id
            releasable_urls << url if url.present?
          end
        end
      end

      # 可删文件 = 可释放 && 不再被任何仍需文件的记录引用
      files_to_delete = releasable_urls.uniq - needed_urls.uniq

      if dry_run
        summary[:records_deleted] += delete_ids.size
        summary[:files_deleted]   += files_to_delete.size
      else
        delete_ids.each_slice(5000) do |batch|
          summary[:records_deleted] += model.where(id: batch).delete_all
        end
        ok, fail = delete_oss_files(files_to_delete)
        summary[:files_deleted] += ok
        summary[:files_failed]  += fail
      end
    end

    puts "[StorageCleaner] clean_published_queues 完成（#{dry_run ? '预览' : '执行'}）：#{summary.inspect}"
    summary
  end

  # ---------- 链路二：源视频 raw OSS 清理 ----------
  # 某条线「不再需要源视频」当且仅当：该线状态已完成（failed_as_done 时也含 failed），
  # 或该主题在该线对应的工作模式下已无正常账号（该线不会再消费这条源视频）。
  # 两条线都不再需要时，才删 raw 文件并置空 raw_oss_url。
  def self.clean_source_videos(dry_run: true, failed_as_done: false)
    done = failed_as_done ? ['completed', 'failed'] : ['completed']
    summary = { raw_cleared: 0, files_deleted: 0, files_failed: 0 }

    move_work_type    = WorkMode.for_model(MoveTask).name
    hunjian_work_type = WorkMode.for_model(HunjianTask).name

    # 预计算：有该工作模式「正常」账号的主题集合
    move_themes    = Account.active.where(work_type: move_work_type).distinct.pluck(:theme)
    hunjian_themes = Account.active.where(work_type: hunjian_work_type).distinct.pluck(:theme)

    MoveVideo.where.not(raw_oss_url: [nil, '']).find_each do |v|
      jianying_done = done.include?(v.jianying_status) || !move_themes.include?(v.theme)
      hunjian_done  = done.include?(v.hunjian_status)  || !hunjian_themes.include?(v.theme)

      next unless jianying_done && hunjian_done

      if dry_run
        summary[:raw_cleared] += 1
      else
        ok, fail = delete_oss_files([v.raw_oss_url])
        summary[:files_deleted] += ok
        summary[:files_failed]  += fail
        v.update_column(:raw_oss_url, nil)
        summary[:raw_cleared] += 1
      end
    end

    puts "[StorageCleaner] clean_source_videos 完成（#{dry_run ? '预览' : '执行'}）：#{summary.inspect}"
    summary
  end

  # ---------- OSS bucket 对象计数（清理前后对比用） ----------
  # 统计某个 bucket 下的对象总数（分页遍历，不遗漏）。
  # 用法： bundle exec rails runner "p StorageCleaner.count_bucket_objects('jianying-videos')"
  def self.count_bucket_objects(bucket_name, prefix: nil)
    return 0 if bucket_name.blank?

    access_key_id, access_key_secret = oss_credentials_for(bucket_name)
    return 0 if access_key_id.blank? || access_key_secret.blank?

    bucket = oss_client(access_key_id, access_key_secret).get_bucket(bucket_name)
    count  = 0
    marker = nil
    loop do
      opts = { max_keys: 1000 }
      opts[:prefix] = prefix if prefix.present?
      opts[:marker]  = marker if marker.present?

      list = bucket.list_objects(opts)
      page = list.respond_to?(:objects) ? list.objects : list.to_a
      count += page.size

      marker = list.respond_to?(:next_marker) ? list.next_marker : nil
      break if marker.blank?
    end
    count
  end

  # 一键统计所有涉及清理的 bucket（清理前跑一次、清理后再跑一次做对比）
  def self.count_all_buckets
    buckets = %w[
      jianying-videos jianying-rd huasheng-ld notebooklm-ld operation-viodes grok-videos
    ]
    buckets.each { |b| puts "#{b}: #{count_bucket_objects(b)}" }
    nil
  end

  # ---------- OSS 删除（尽力而为，404 视为已不存在） ----------
  def self.delete_oss_files(urls)
    return [0, 0] if urls.blank?
    ok = fail = 0
    urls.each_with_index do |url, i|
      status, = delete_one_oss(url)
      if status == :ok
        ok += 1
      else
        fail += 1
      end
      puts "[StorageCleaner] OSS 删除进度 #{i + 1}/#{urls.size}" if ((i + 1) % 100).zero?
    end
    [ok, fail]
  end

  def self.delete_one_oss(url)
    return [:skip, 'URL 为空'] if url.blank?

    bucket, key = parse_oss_url(url)
    return [:fail, "无法解析 bucket/key: #{url[0, 80]}"] if bucket.blank? || key.blank?

    access_key_id, access_key_secret = oss_credentials_for(bucket)
    return [:skip, "OSS 凭证未配置（bucket=#{bucket}）"] if access_key_id.blank? || access_key_secret.blank?

    oss_client(access_key_id, access_key_secret).get_bucket(bucket).delete_object(key)
    [:ok, nil]
  rescue => e
    msg = e.message.to_s
    if msg.include?('404') || msg.include?('NoSuchKey') || msg.include?('NoSuchFile')
      [:ok, '对象已不存在']
    else
      [:fail, msg]
    end
  end

  # 根据 bucket 名取对应的 OSS 凭证（TWO_KEY_BUCKETS → TWO 账号，其余 → 主账号）
  def self.oss_credentials_for(bucket)
    if TWO_KEY_BUCKETS.include?(bucket)
      [ENV['ALIYUN_ACCESS_TWO_KEY_ID'], ENV['ALIYUN_ACCESS_TWO_KEY_SECRET']]
    else
      [ENV['ALIYUN_ACCESS_KEY_ID'], ENV['ALIYUN_ACCESS_KEY_SECRET']]
    end
  end

  # 按凭证组懒加载 OSS client（两组凭证各缓存一个实例）
  def self.oss_client(access_key_id, access_key_secret)
    @oss_clients ||= {}
    @oss_clients[[access_key_id, access_key_secret]] ||= begin
      require 'aliyun/oss'
      Aliyun::OSS::Client.new(
        endpoint: OSS_ENDPOINT,
        access_key_id: access_key_id,
        access_key_secret: access_key_secret
      )
    end
  end

  def self.parse_oss_url(url)
    require 'uri'
    uri = URI.parse(url.to_s)
    bucket = uri.host.to_s.split('.').first
    key = uri.path.to_s.sub(%r{\A/}, '')
    begin
      key = URI.decode_www_form_component(key)
    rescue StandardError
      # 解码失败则用原始 path
    end
    [bucket, key]
  end
end
