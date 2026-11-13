# == Schema Information
#
# Table name: external_publish_tasks
#
#  id                   :bigint           not null, primary key
#  actual_publish_time  :datetime
#  error_msg            :text(65535)
#  failure_count        :integer          default(0), not null
#  media_type           :integer          default("image"), not null
#  media_urls           :text(65535)
#  platform             :integer
#  start_at             :datetime
#  status               :integer          default("pending"), not null
#  task_uuid            :string(255)
#  text                 :text(65535)
#  theme                :string(255)
#  title                :string(255)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint
#  browser_id           :bigint
#  external_resource_id :bigint
#
# Indexes
#
#  index_external_publish_tasks_on_account_id            (account_id)
#  index_external_publish_tasks_on_external_resource_id  (external_resource_id)
#  index_external_publish_tasks_on_platform              (platform)
#  index_external_publish_tasks_on_status                (status)
#  index_external_publish_tasks_on_task_uuid             (task_uuid) UNIQUE
#  index_external_publish_tasks_on_theme                 (theme)
#
class ExternalPublishTask < ApplicationRecord
  serialize :media_urls, JSON

  belongs_to :external_resource, optional: true
  belongs_to :account, optional: true
  belongs_to :browser, optional: true

  has_many :task_logs, foreign_key: :task_uuid, primary_key: :task_uuid, dependent: :nullify

  # 状态枚举与现有任务模型（GrokTask 等）保持一致，确保 PublishScheduler 通用逻辑可复用
  enum status: {
    pending: 0,
    waiting_publish: 1,
    executing: 2,
    success: 3,
    failed: 4,
    claimed: 5
  }

  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  # 媒体形态：主媒体类型（text 字段独立，可与任意媒体形态组合）
  enum media_type: {
    video: 0,
    image: 1,
    text: 2
  }

  validates :theme, :task_uuid, presence: true
  validates :task_uuid, uniqueness: true

  before_validation :generate_task_uuid, on: :create

  def media_urls
    super || []
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme platform media_type status account_id browser_id task_uuid external_resource_id title created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[external_resource account browser]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= SecureRandom.uuid
  end
end
