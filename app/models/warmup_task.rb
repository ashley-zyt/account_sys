# == Schema Information
#
# Table name: warmup_tasks
#
#  id                :bigint           not null, primary key
#  account_id        :bigint
#  browser_id        :bigint
#  platform          :integer
#  operations        :text(65535)
#  status            :integer          default("pending")
#  error_msg         :text(65535)
#  executed_at       :datetime
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  task_uuid         :string(255)
#  duration_minutes  :integer
#  machine           :string(255)
#

class WarmupTask < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :browser, optional: true

  before_create :generate_task_uuid

  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  enum status: {
    pending: 0,
    executing: 1,
    success: 2,
    failed: 3
  }

  validates :task_uuid, presence: true, uniqueness: true

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      account_id
      browser_id
      platform
      status
      executed_at
      created_at
      updated_at
      task_uuid
      duration_minutes
      machine
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account", "browser"]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= SecureRandom.uuid
  end
end