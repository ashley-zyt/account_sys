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
#  processed_oss_url(剪映处理后 OSS URL（发布用）)                                       :text(65535)
#  raw_oss_url(下载后原始视频 OSS URL)                                                   :text(65535)
#  source_account_url(来源账号主页链接)                                                  :string(255)
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

  DEFAULT_PLATFORMS = %w[youtube facebook twitter tiktok].freeze

  enum status: {
    pending_download: 0,  # 待下载（录入后初始）
    downloading: 1,       # 下载中（下载软件已 claim，回调前）
    pending_process: 2,   # 待剪映处理（下载完成，raw_oss_url 已回写）
    processing: 3,        # 剪映处理中（剪映项目已 claim，回调前）
    processed: 4,         # 剪映完成（可发布）
    failed: 5             # 失败（暂为终态，重试逻辑后续补）
  }

  validates :source_video_url, presence: true, uniqueness: true
  validates :group_id, presence: true

  scope :pending_download, -> { where(status: :pending_download) }
  scope :pending_process, -> { where(status: :pending_process) }

  def self.ransackable_attributes(auth_object = nil)
    %w[id source_video_url source_account_url theme group_id platforms status
       raw_oss_url error_msg created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[move_tasks]
  end

  # 状态中文标签（admin 展示用）
  STATUS_LABELS = {
    'pending_download' => '待下载',
    'downloading' => '下载中',
    'pending_process' => '待剪映',
    'processing' => '剪映中',
    'processed' => '已完成',
    'failed' => '失败'
  }.freeze

  def self.human_status(status)
    key = status.to_s
    STATUS_LABELS[key] || key
  end

  def human_status
    self.class.human_status(status)
  end

  # 录入：find_or_create 幂等，重复录入同一 source_video_url 返回已存在记录，不重置状态
  def self.create_from_import!(source_video_url:, source_account_url:, theme:, platforms:)
    find_or_create_by!(source_video_url: source_video_url) do |v|
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

  # ---------- 下载阶段领取（原子） ----------
  # 拉取一条 pending_download 并原子置为 downloading，并发安全
  # @return [MoveVideo, nil] 领取到的视频（已 reload 为 downloading），无则 nil
  def self.claim_for_download!
    pending_download.order(created_at: :asc).limit(50).each do |record|
      return record if record.claim_download!
    end
    nil
  end

  def claim_download!
    now = Time.current
    updated = self.class
      .where(id: id, status: MoveVideo.statuses[:pending_download])
      .update_all(status: MoveVideo.statuses[:downloading], download_started_at: now, updated_at: now)
    updated == 1 ? reload : false
  end

  # 下载完成回调：downloading → pending_process，写 raw_oss_url
  def mark_downloaded!(raw_oss_url)
    raise StateError, "当前状态 #{status} 不允许标记下载完成" unless downloading?
    update!(
      status: :pending_process,
      raw_oss_url: raw_oss_url,
      downloaded_at: Time.current,
      error_msg: nil
    )
  end

  # ---------- 剪映阶段领取（原子） ----------
  # 拉取一条 pending_process 并原子置为 processing，并发安全
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
      .where(id: id, status: MoveVideo.statuses[:pending_process])
      .update_all(status: MoveVideo.statuses[:processing], process_started_at: now, updated_at: now)
    updated == 1 ? reload : false
  end

  # 剪映完成回调：processing → processed，并按 platforms 创建多平台 move_task
  # 成片 OSS URL 写到每条 move_task.oss_url（与 jianying_task 等资源队列一致，发布时直接用）
  def mark_processed!(processed_oss_url)
    raise StateError, "当前状态 #{status} 不允许标记剪映完成" unless processing?

    transaction do
      update!(
        status: :processed,
        processed_at: Time.current,
        error_msg: nil
      )
      create_move_tasks!(processed_oss_url)
    end
  end

  # 失败回调：暂为终态（重试逻辑后续补）
  def mark_failed!(error_msg)
    update!(status: :failed, error_msg: error_msg)
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

  class StateError < StandardError; end
end
