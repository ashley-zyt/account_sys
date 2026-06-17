class GrokVideoResource < ApplicationRecord
  belongs_to :grok_image_resource, optional: true
  belongs_to :account, optional: true
  belongs_to :browser, optional: true

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

  validates :theme, :prompt, :task_uuid, presence: true
  validates :task_uuid, uniqueness: true

  before_validation :generate_task_uuid, on: :create

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme video_url status prompt grok_image_id account_id browser_id task_uuid platform title description created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    ["grok_image_resource", "account", "browser"]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= SecureRandom.uuid
  end
end