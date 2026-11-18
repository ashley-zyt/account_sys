# == Schema Information
#
# Table name: direct_publish_logs
#
#  id                  :bigint           not null, primary key
#  actual_publish_time :datetime
#  description         :text(65535)
#  error_msg           :text(65535)
#  media_type          :integer          default("image"), not null
#  media_urls          :text(65535)
#  platform            :string(255)
#  publish_channel     :string(255)
#  status              :integer          default("pending"), not null
#  task_uuid           :string(255)
#  text                :text(65535)
#  title               :string(255)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint
#  external_id         :string(255)
#
# Indexes
#
#  index_direct_publish_logs_on_account_id       (account_id)
#  index_direct_publish_logs_on_platform         (platform)
#  index_direct_publish_logs_on_publish_channel  (publish_channel)
#  index_direct_publish_logs_on_status           (status)
#  index_direct_publish_logs_on_task_uuid        (task_uuid) UNIQUE
#
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
