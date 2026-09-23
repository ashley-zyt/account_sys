# == Schema Information
#
# Table name: move_videos
#
#  id                                                                                    :bigint           not null, primary key
#  download_started_at(下载领取时间)                                                     :datetime
#  downloaded_at(下载完成时间)                                                           :datetime
#  error_msg(错误信息/失败原因)                                                          :text(65535)
#  platforms(目标平台列表，逗号分隔，如 youtube,facebook,twitter,tiktok)                 :string(255)
#  process_started_at(剪映领取时间)                                                      :datetime
#  processed_at(剪映完成时间)                                                            :datetime
#  raw_oss_url(下载后原始视频 OSS URL)                                                   :text(65535)
#  source_account_url(来源账号主页链接)                                                  :string(255)
#  source_title(原视频标题)                                                              :string(255)
#  source_video_url(源视频链接（核心幂等）)                                              :string(255)      not null
#  status(状态 pending_download/downloading/pending_process/processing/processed/failed) :integer          default("pending_download"), not null
#  theme(内容主题)                                                                       :string(255)
#  created_at                                                                            :datetime         not null
#  updated_at                                                                            :datetime         not null
#  group_id(视频组UUID，多平台 move_task 共享)                                           :string(255)      not null
#
# Indexes
#
#  idx_move_videos_source_video_url  (source_video_url) UNIQUE
#  idx_move_videos_status_created    (status,created_at)
#  index_move_videos_on_group_id     (group_id)
#  index_move_videos_on_status       (status)
#
class MoveVideo < ApplicationRecord
  has_many :move_tasks, dependent: :nullify

  DEFAULT_PLATFORMS = %w[youtube instagram twitter tiktok].freeze

  # 下载状态（status）：只跟踪「源视频是否已下载到 OSS」
  enum status: {
    pending_download: 0,  # 待下载（录入后初始）
    downloading: 1,       # 下载中（下载软件已 claim，回调前）
    downloaded: 2,        # 下载完成（raw_oss_url 已回写）
    failed: 3             # 下载失败
  }

  # 剪映流程状态（与混剪并行，互不影响）
  enum jianying_status: {
    pending: 0,     # 待剪映
    processing: 1,  # 剪映中
    completed: 2,   # 已完成
    failed: 3       # 失败
  }

  # 混剪流程状态（与剪映并行，互不影响）
  enum hunjian_status: {
    pending: 0,     # 待混剪
    processing: 1,  # 混剪中
    completed: 2,   # 已完成
    failed: 3       # 失败
  }

  validates :source_video_url, presence: true, uniqueness: true
  validates :group_id, presence: true

  scope :pending_download, -> { where(status: :pending_download) }
  # 待剪映：下载完成 + 剪映流程未开始
  scope :pending_process, -> { where(status: :downloaded, jianying_status: :pending) }
  # 待混剪：下载完成 + 混剪流程未开始
  scope :pending_hunjian, -> { where(status: :downloaded, hunjian_status: :pending) }

  def self.ransackable_attributes(auth_object = nil)
    %w[id source_video_url source_title source_account_url theme group_id platforms status
       jianying_status hunjian_status raw_oss_url error_msg created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[move_tasks]
  end

  # 状态中文标签（admin 展示用）
  STATUS_LABELS = {
    'pending_download' => '待下载',
    'downloading' => '下载中',
    'downloaded' => '已下载',
    'failed' => '下载失败'
  }.freeze

  JIANYING_STATUS_LABELS = {
    'pending' => '待剪映',
    'processing' => '剪映中',
    'completed' => '已完成',
    'failed' => '剪映失败'
  }.freeze

  HUNJIAN_STATUS_LABELS = {
    'pending' => '待混剪',
    'processing' => '混剪中',
    'completed' => '已完成',
    'failed' => '混剪失败'
  }.freeze

  def self.human_status(status)
    key = status.to_s
    STATUS_LABELS[key] || key
  end

  def human_status
    self.class.human_status(status)
  end

  def jianying_status_label
    JIANYING_STATUS_LABELS[jianying_status] || jianying_status
  end

  def hunjian_status_label
    HUNJIAN_STATUS_LABELS[hunjian_status] || hunjian_status
  end

  # 录入：find_or_create 幂等，重复录入同一 source_video_url 返回已存在记录，不重置状态
  def self.create_from_import!(source_video_url:, source_account_url:, theme:, platforms:, source_title: nil)
    find_or_create_by!(source_video_url: source_video_url) do |v|
      v.source_title = source_title
      v.source_account_url = source_account_url
      v.theme = theme
      v.group_id = SecureRandom.uuid
      v.platforms = platforms
      v.status = :pending_download
    end
  end

  # 从 backup_unpublished_video_urls 产生的 JSON 批量导入历史未发布视频
  # 去重策略（双重保障）：
  #   1. 内存去重：按 source_video_url 去重，JSON 内重复的只保留首条
  #   2. DB 去重：find_or_create_by + source_video_url UNIQUE 索引，已存在的跳过（不覆盖进度）
  # 已存在的 move_video 不更新（避免覆盖已下载/已剪映的进度），仅新建缺失的为 pending_download
  # @param path [String, Pathname] 备份 JSON 文件路径
  # @return [Hash] { path:, total_records:, unique_records:, created:, skipped:, failed: }
  def self.import_from_backup!(path:)
    path = path.to_s
    raise "备份文件不存在：#{path}" unless File.exist?(path)

    records = Array(JSON.parse(File.read(path))["records"])

    # 内存去重：按 source_video_url 去重，保留首条
    seen = {}
    unique_records = records.each_with_object([]) do |record, acc|
      video_url = record["video_url"].to_s.strip
      next if video_url.blank? || seen.key?(video_url)
      seen[video_url] = true
      acc << record
    end

    created = 0
    skipped = 0
    failed = 0

    unique_records.each do |record|
      video_url = record["video_url"].to_s.strip
      platforms = Array(record["platforms"]).map(&:to_s).reject(&:blank?).join(",")
      platforms = DEFAULT_PLATFORMS.join(",") if platforms.blank?

      existed = exists?(source_video_url: video_url)
      find_or_create_by!(source_video_url: video_url) do |v|
        v.source_title = record["source_title"].presence || record["title"]
        v.source_account_url = record["source_account_url"]
        v.theme = record["theme"]
        v.group_id = record["group_id"].presence || SecureRandom.uuid
        v.platforms = platforms
        v.status = :pending_download
      end
      existed ? skipped += 1 : created += 1
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      failed += 1
      warn "导入失败 video_url=#{video_url}：#{e.message}"
    end

    {
      path: path,
      total_records: records.size,
      unique_records: unique_records.size,
      created: created,
      skipped: skipped,
      failed: failed
    }
  end

  # ---------- 下载阶段领取（原子 + 主题轮询） ----------
  # 拉取一条 pending_download 并原子置为 downloading，并发安全
  # 主题轮询：每次选取「最近一次领取时间最早」的主题（从未领取过的优先），
  # 再从该主题取最早录入的一条。这样多次调用会按主题轮流获取（A→B→C→A…）。
  # 无需额外存储游标，基于 download_started_at 历史，跨进程/跨重启均有效。
  # @return [MoveVideo, nil] 领取到的视频（已 reload 为 downloading），无则 nil
  def self.claim_for_download!
    theme = next_download_theme
    candidates = theme ? pending_download.where(theme: theme) : pending_download

    candidates.order(created_at: :asc).limit(50).each do |record|
      return record if record.claim_download!
    end
    nil
  end

  # 选下一个要领取的主题：在有待下载视频的主题中，选「最近领取时间最早」的
  # 从未领取过的主题（download_started_at 为 NULL）优先，保证每个主题都能被轮到
  # @return [String, nil] 主题名；无待下载视频时返回 nil
  def self.next_download_theme
    themes = pending_download.where.not(theme: [nil, '']).distinct.pluck(:theme)
    return nil if themes.empty?

    last_claimed = where(theme: themes).group(:theme).maximum(:download_started_at)

    themes.min_by do |t|
      claimed = last_claimed[t]
      [claimed ? 1 : 0, claimed || Time.at(0), t]
    end
  end

  def claim_download!
    now = Time.current
    updated = self.class
      .where(id: id, status: MoveVideo.statuses[:pending_download])
      .update_all(status: MoveVideo.statuses[:downloading], download_started_at: now, updated_at: now)
    updated == 1 ? reload : false
  end

  # 下载完成回调：downloading → downloaded，写 raw_oss_url，两个流程均进入「待」状态
  def mark_downloaded!(raw_oss_url)
    raise StateError, "当前状态 #{status} 不允许标记下载完成" unless downloading?
    update!(
      status: :downloaded,
      jianying_status: :pending,
      hunjian_status: :pending,
      raw_oss_url: raw_oss_url,
      downloaded_at: Time.current,
      error_msg: nil
    )
  end

  # ---------- 剪映阶段领取（原子） ----------
  # 拉取一条「待剪映」并原子置为「剪映中」，并发安全
  # @return [MoveVideo, nil]
  def self.claim_for_processing!
    pending_process.order(created_at: :asc).limit(50).each do |record|
      return record if record.claim_process!
    end
    nil
  end

  def claim_process!
    now = Time.current
    updated = self.class
      .where(id: id, status: MoveVideo.statuses[:downloaded], jianying_status: MoveVideo.jianying_statuses[:pending])
      .update_all(jianying_status: MoveVideo.jianying_statuses[:processing], process_started_at: now, updated_at: now)
    updated == 1 ? reload : false
  end

  # 剪映完成回调：剪映中 → 已完成，并按 platforms 创建多平台 move_task
  # 成片 OSS URL 写到每条 move_task.oss_url（与 jianying_task 等资源队列一致，发布时直接用）
  def mark_processed!(processed_oss_url)
    raise StateError, "当前剪映状态 #{jianying_status} 不允许标记剪映完成" unless jianying_processing?

    transaction do
      update!(
        jianying_status: :completed,
        processed_at: Time.current,
        error_msg: nil
      )
      create_move_tasks!(processed_oss_url)
    end
  end

  # ---------- 混剪阶段领取（原子） ----------
  # 拉取一条「待混剪」并原子置为「混剪中」，并发安全
  # @return [MoveVideo, nil]
  def self.claim_for_hunjian!
    pending_hunjian.order(created_at: :asc).limit(100).each do |record|
      return record if record.claim_hunjian!
    end
    nil
  end

  # 批量认领「待混剪」源视频（混剪程序一次性认领一大批，逐个处理）
  # @param limit [Integer] 最多认领条数
  # @return [Array<MoveVideo>] 成功认领的视频（已置「混剪中」）
  def self.claim_hunjian_batch!(limit: 100)
    claimed = []
    pending_hunjian.order(created_at: :asc).limit(limit).each do |record|
      claimed << record if record.claim_hunjian!
    end
    claimed
  end

  def claim_hunjian!
    now = Time.current
    updated = self.class
      .where(id: id, status: MoveVideo.statuses[:downloaded], hunjian_status: MoveVideo.hunjian_statuses[:pending])
      .update_all(hunjian_status: MoveVideo.hunjian_statuses[:processing], process_started_at: now, updated_at: now)
    updated == 1 ? reload : false
  end

  # 混剪完成回调：混剪中 → 已完成
  def mark_hunjian_completed!
    raise StateError, "当前混剪状态 #{hunjian_status} 不允许标记混剪完成" unless hunjian_processing?
    update!(hunjian_status: :completed, error_msg: nil)
  end

  # 混剪失败回调：混剪中 → 失败
  def mark_hunjian_failed!(error_msg)
    update!(hunjian_status: :failed, error_msg: error_msg)
  end

  # 下载失败回调
  def mark_download_failed!(error_msg)
    update!(status: :failed, error_msg: error_msg)
  end

  # 剪映失败回调
  def mark_jianying_failed!(error_msg)
    update!(jianying_status: :failed, error_msg: error_msg)
  end

  # ---------- 私有 ----------

  # 剪映成功后，按 platforms 为每个平台创建一条 move_task（pending）
  # (move_video_id, platform) 唯一索引兜底幂等
  # 成片 OSS URL 写入 move_task.oss_url，发布时直接读取
  def create_move_tasks!(processed_oss_url)
    platforms_list.each do |platform_name|
      platform_value = MoveTask.platforms[platform_name.strip.to_sym]
      next unless platform_value

      MoveTask.find_or_create_by!(move_video_id: id, platform: platform_value) do |t|
        t.theme = theme
        t.title = ThemeConfig.random_title(theme)
        t.group_id = group_id
        t.status = :pending
        t.oss_url = processed_oss_url
      end
    end
  end

  # 平台列表（逗号分隔 → 数组），缺省回退到默认 4 平台
  def platforms_list
    raw = platforms.to_s.strip
    list = raw.split(',').map(&:strip).reject(&:blank?)
    list.any? ? list : DEFAULT_PLATFORMS
  end

  # ---------- 删除（含 OSS 同步删除） ----------
  # OSS 杭州区域 endpoint（bucket 名从 URL host 自动解析，无需硬编码）
  OSS_ENDPOINT = 'https://oss-cn-hangzhou.aliyuncs.com'.freeze

  # 删除单条 move_video，并同步删除其名下的 OSS 视频文件（原始视频 raw_oss_url + 关联成片）。
  #
  # 策略：
  #   1. 先收集要删的 OSS URL（删库前必须拿到，记录删完就无法回溯）
  #   2. 事务内删除 DB 记录（move_tasks 可选连带删除，move_video 本体 destroy!）
  #   3. 事务外删除 OSS 文件（尽力而为：404 视为已不存在，OSS 失败不影响 DB 删除结果）
  #
  # @param delete_move_tasks [Boolean] 是否连带删除关联 move_tasks 及其成片 OSS
  #        true  → 彻底删除这条视频的所有产物（raw 原始视频 + 成片 + move_tasks 记录）
  #        false → 只删 move_video 与 raw 原始视频；move_tasks 走 dependent: :nullify 保留，成片 OSS 不动
  # @param delete_oss [Boolean] 是否删除 OSS 文件，默认 true（置 false 可只删库、留文件）
  # @return [Hash] { deleted_video:, deleted_tasks:, oss_ok:, oss_failed:, oss_skipped:, oss_urls:, oss_errors: }
  def destroy_with_oss!(delete_move_tasks: true, delete_oss: true)
    # ① 先收集要删的 OSS URL
    oss_urls = []
    oss_urls << raw_oss_url if raw_oss_url.present?
    oss_urls += move_tasks.where.not(oss_url: [nil, '']).pluck(:oss_url) if delete_move_tasks
    oss_urls = oss_urls.compact.map(&:to_s).reject(&:blank?).uniq

    deleted_tasks = 0
    transaction do
      deleted_tasks = move_tasks.delete_all if delete_move_tasks
      # delete_move_tasks=false 时，剩余 move_tasks 由 dependent: :nullify 置空引用并保留
      destroy!
    end

    # ② 删除 OSS 文件（尽力而为，失败只记录不抛出）
    oss_ok = oss_failed = oss_skipped = 0
    oss_errors = []
    if delete_oss
      oss_urls.each do |url|
        status, msg = self.class.send(:delete_oss_object, url)
        case status
        when :ok   then oss_ok += 1
        when :skip then oss_skipped += 1
        when :fail
          oss_failed += 1
          oss_errors << "#{url[0, 80]}: #{msg}"
        end
      end
    else
      oss_skipped = oss_urls.size
    end

    {
      deleted_video: 1,
      deleted_tasks: deleted_tasks,
      oss_ok: oss_ok,
      oss_failed: oss_failed,
      oss_skipped: oss_skipped,
      oss_urls: oss_urls,
      oss_errors: oss_errors
    }
  end

  # 批量删除：对传入的集合逐条调用 destroy_with_oss!，返回汇总统计。
  # 用法示例：
  #   MoveVideo.destroy_all_with_oss!(MoveVideo.where(status: :failed))
  #   MoveVideo.destroy_all_with_oss!(MoveVideo.where('created_at < ?', 7.days.ago))
  #   MoveVideo.destroy_all_with_oss!(MoveVideo.where(id: [1, 2, 3]), delete_move_tasks: false)
  # @return [Hash] { deleted_video:, deleted_tasks:, oss_ok:, oss_failed:, oss_skipped:, oss_errors: }
  def self.destroy_all_with_oss!(records = nil, delete_move_tasks: true, delete_oss: true)
    records ||= all
    summary = { deleted_video: 0, deleted_tasks: 0, oss_ok: 0, oss_failed: 0, oss_skipped: 0, oss_errors: [] }
    records.find_each do |video|
      r = video.destroy_with_oss!(delete_move_tasks: delete_move_tasks, delete_oss: delete_oss)
      summary[:deleted_video] += r[:deleted_video]
      summary[:deleted_tasks] += r[:deleted_tasks]
      summary[:oss_ok] += r[:oss_ok]
      summary[:oss_failed] += r[:oss_failed]
      summary[:oss_skipped] += r[:oss_skipped]
      summary[:oss_errors].concat(r[:oss_errors])
    end
    summary
  end

  class << self
    private

    # OSS 凭证是否已配置
    def oss_credentials_configured?
      ENV['ALIYUN_ACCESS_KEY_ID'].present? && ENV['ALIYUN_ACCESS_KEY_SECRET'].present?
    end

    # 从 OSS URL 解析 bucket 与 key（兼容签名 URL，query 参数忽略）
    def parse_oss_url(url)
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

    # 懒加载 OSS client（复用，避免每个文件新建）
    def oss_client
      @oss_client ||= begin
        require 'aliyun/oss'
        Aliyun::OSS::Client.new(
          endpoint: OSS_ENDPOINT,
          access_key_id: ENV['ALIYUN_ACCESS_KEY_ID'],
          access_key_secret: ENV['ALIYUN_ACCESS_KEY_SECRET']
        )
      end
    end

    # 删除单个 OSS 对象，返回 [结果, 消息]；404 视为「已不存在」算成功
    def delete_oss_object(url)
      return [:skip, 'URL 为空'] if url.blank?
      return [:skip, 'OSS 凭证未配置'] unless oss_credentials_configured?

      bucket, key = parse_oss_url(url)
      return [:fail, "无法解析 bucket/key: #{url[0, 80]}"] if bucket.blank? || key.blank?

      oss_client.get_bucket(bucket).delete_object(key)
      [:ok, nil]
    rescue => e
      msg = e.message.to_s
      if msg.include?('404') || msg.include?('NoSuchKey') || msg.include?('NoSuchFile')
        [:ok, '对象已不存在']
      else
        [:fail, msg]
      end
    end
  end

  class StateError < StandardError; end
end
