# == Schema Information
#
# Table name: heygen_tasks
#
#  id                                                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                                 :datetime
#  description(描述)                                                 :text(65535)
#  error_msg(任务结果)                                               :text(65535)
#  platform(平台)                                                    :integer
#  start_at(任务开始时间)                                            :datetime
#  status(任务状态 pending/waiting_publish/executing/success/failed) :integer          default("pending")
#  task_uuid(任务唯一标识，用于关联日志)                             :string(255)
#  theme(主题)                                                       :string(255)
#  title(标题)                                                       :text(65535)
#  video_text(逐字稿)                                                :text(65535)
#  video_url(视频OSSurl)                                             :text(65535)
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  account_id(账号ID)                                                :bigint
#  browser_id(浏览器ID)                                              :bigint
#  templete_id(视频模板ID)                                           :string(255)
#
# Indexes
#
#  index_heygen_tasks_on_account_id   (account_id)
#  index_heygen_tasks_on_browser_id   (browser_id)
#  index_heygen_tasks_on_platform     (platform)
#  index_heygen_tasks_on_status       (status)
#  index_heygen_tasks_on_task_uuid    (task_uuid) UNIQUE
#  index_heygen_tasks_on_templete_id  (templete_id)
#  index_heygen_tasks_on_theme        (theme)
#
class HeygenTask < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :browser, optional: true

  has_many :task_logs, foreign_key: :task_uuid, primary_key: :task_uuid, dependent: :nullify

  enum status: {
    pending: 0,
    waiting_publish: 1,
    executing: 2,
    success: 3,
    failed: 4
  }

  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  validates :task_uuid, presence: true, uniqueness: true
  validates :theme, presence: true

  before_validation :generate_task_uuid, on: :create

  scope :runnable, -> {
    where(status: :waiting_publish)
  }

  scope :pending_for_theme, ->(theme) {
    where(status: :pending, theme: theme).order(created_at: :asc)
  }

  scope :recent, -> {
    order(created_at: :desc)
  }

  scope :executing_with_video, -> {
    executing.where.not(templete_id: nil)
  }

  def reset_to_pending!
    update!(
      account_id: nil,
      browser_id: nil,
      status: :pending,
      start_at: nil
    )
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme video_url status templete_id video_text account_id browser_id error_msg start_at actual_publish_time task_uuid platform title description created_at updated_at video_status]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account browser]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= "HG-#{SecureRandom.uuid}"
  end
end
