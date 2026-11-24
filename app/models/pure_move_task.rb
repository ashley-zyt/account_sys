# == Schema Information
#
# Table name: pure_move_tasks
#
#  id                                                                        :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                                         :datetime
#  description(视频描述)                                                     :string(255)
#  error_msg(错误信息/失败原因)                                              :text(65535)
#  failure_count(发布失败次数，累计达到上限即判定资源不可用并删除)           :integer          default(0), not null
#  oss_url(源视频 OSS 签名 URL（下载后的原始视频）)                          :text(65535)
#  platform(目标发布平台)                                                    :integer
#  start_at(任务开始时间)                                                    :datetime
#  status(任务状态 pending/waiting_publish/executing/success/failed/claimed) :integer          default("pending")
#  task_uuid(任务唯一标识，用于关联日志)                                     :string(255)
#  theme(内容主题)                                                           :string(255)
#  title(发布标题)                                                           :text(65535)
#  created_at                                                                :datetime         not null
#  updated_at                                                                :datetime         not null
#  account_id(发布账号ID)                                                    :bigint
#  browser_id(执行任务的浏览器ID)                                            :bigint
#  group_id(任务组ID（同一源视频的多平台任务共享）)                          :string(255)
#  move_video_id(源视频ID（搬运资源储备 move_videos.id）)                    :bigint
#
# Indexes
#
#  index_pure_move_tasks_on_account_id                  (account_id)
#  index_pure_move_tasks_on_browser_id                  (browser_id)
#  index_pure_move_tasks_on_group_id                    (group_id)
#  index_pure_move_tasks_on_move_video_id_and_platform  (move_video_id,platform) UNIQUE
#  index_pure_move_tasks_on_platform                    (platform)
#  index_pure_move_tasks_on_status                      (status)
#  index_pure_move_tasks_on_task_uuid                   (task_uuid) UNIQUE
#  index_pure_move_tasks_on_theme                       (theme)
#
class PureMoveTask < ApplicationRecord
  belongs_to :browser, optional: true
  belongs_to :account, optional: true
  belongs_to :move_video, optional: true

  enum status: {
    pending: 0,          # 待分配账号
    waiting_publish: 1,  # 等待发布
    executing: 2,        # 执行中
    success: 3,          # 成功
    failed: 4,           # 失败
    claimed: 5           # 人工认领（终态，系统不再发布）
  }
  # 平台枚举（与 Account.platform 完全一致）
  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  validates :task_uuid, presence: true, uniqueness: true
  # 非 pending 状态必须有账号
  validates :account_id, presence: true, unless: :pending?
  validates :platform, presence: true
  validates :group_id, presence: true
  validates :move_video_id, uniqueness: { scope: :platform, message: '该视频在此平台已存在任务' }

  before_validation :generate_task_uuid, on: :create
  before_validation :assign_group_id, on: :create

  scope :runnable, -> { where(status: :waiting_publish) }

  scope :pending_for_platform, ->(platform) {
    where(status: :pending, platform: platform).order(created_at: :asc)
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id task_uuid theme title description oss_url platform
      account_id browser_id move_video_id status error_msg
      start_at actual_publish_time group_id failure_count created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account", "browser", "move_video"]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= "PUREMOVE-#{SecureRandom.uuid}"
  end

  def assign_group_id
    self.group_id ||= SecureRandom.uuid
  end
end
