# == Schema Information
#
# Table name: hunjian_tasks
#
#  id                                                              :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                               :datetime
#  description(视频描述)                                           :string(255)
#  error_msg(错误信息/失败原因)                                    :text(65535)
#  full_oss_url(混剪成品 OSS object key)                           :text(65535)
#  group_id(任务组ID)                                              :string(255)
#  move_video_ids(源视频ID，逗号分隔)                              :string(255)
#  oss_url(混剪成品 OSS 签名 URL)                                  :text(65535)
#  platform(目标发布平台)                                          :integer
#  start_at(任务开始时间)                                          :datetime
#  status(任务状态 pending/waiting_publish/executing/success/failed) :integer          default("pending")
#  task_uuid(任务唯一标识)                                         :string(255)
#  theme(内容主题)                                                 :string(255)
#  title(发布标题)                                                 :text(65535)
#  created_at                                                      :datetime         not null
#  updated_at                                                      :datetime         not null
#  account_id(发布账号ID)                                          :bigint
#  browser_id(执行任务的浏览器ID)                                  :bigint
#
class HunjianTask < ApplicationRecord
  belongs_to :browser, optional: true
  belongs_to :account, optional: true
  before_validation :generate_task_uuid, on: :create

  enum status: {
    pending: 0,          # 待分配账号
    waiting_publish: 1,  # 等待发布
    executing: 2,        # 执行中
    success: 3,          # 成功
    failed: 4            # 失败
  }

  # 平台枚举（与 MoveTask / Account.platform 完全一致）
  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  validates :task_uuid, presence: true, uniqueness: true
  validates :oss_url, presence: true
  validates :platform, presence: true
  validates :group_id, presence: true
  # 非 pending 状态必须有账号
  validates :account_id, presence: true, unless: :pending?

  # 解析 move_video_ids 为整数数组（混剪为 2 个源视频）
  def move_video_id_list
    move_video_ids.to_s.split(',').map(&:strip).map(&:to_i).reject(&:zero?)
  end

  # 关联的源视频（按 move_video_ids 顺序）
  def move_videos
    ids = move_video_id_list
    return MoveVideo.none if ids.empty?
    MoveVideo.where(id: ids).order("FIELD(id, #{ids.join(',')})")
  end

  # 混剪完成回传：按 platforms 为每个平台创建一条 hunjian_task（pending）
  # @return [Integer] 创建的任务数
  def self.create_from_hunjian_result!(move_video_ids:, oss_url:, full_oss_url: nil,
                                       title:, description: nil, platforms:, theme:, group_id: nil)
    platform_names = platforms.to_s.split(',').map(&:strip).reject(&:blank?)
    gid = group_id.presence || SecureRandom.uuid
    created = 0

    platform_names.each do |platform_name|
      next unless platforms.key?(platform_name.to_sym)

      create!(
        move_video_ids: Array(move_video_ids).join(','),
        oss_url: oss_url,
        full_oss_url: full_oss_url,
        title: title,
        description: description,
        platform: platform_name,
        theme: theme,
        group_id: gid,
        status: :pending
      )
      created += 1
    end

    created
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id task_uuid move_video_ids theme title description oss_url full_oss_url
       platform account_id browser_id group_id status error_msg start_at
       actual_publish_time created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account browser]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= "HJ-#{SecureRandom.uuid}"
  end
end
