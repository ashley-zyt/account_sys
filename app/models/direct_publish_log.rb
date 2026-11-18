# 外部直发记录：外部 agent 通过 /api/v1/publish 直接调本系统已授权的第三方渠道发布时，落一条记录供追溯。
class DirectPublishLog < ApplicationRecord
  serialize :media_urls, JSON

  belongs_to :account, optional: true

  enum media_type: {
    video: 0,
    image: 1,
    text: 2
  }

  enum status: {
    pending: 0,
    success: 1,
    failed: 2
  }

  before_validation :generate_task_uuid, on: :create

  def media_urls
    super || []
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id account_id platform media_type publish_channel status external_id task_uuid created_at updated_at]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= SecureRandom.uuid
  end
end
