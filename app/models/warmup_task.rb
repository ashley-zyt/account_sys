# == Schema Information
#
# Table name: warmup_tasks
#
#  id               :bigint           not null, primary key
#  duration_minutes :integer
#  error_msg        :text(65535)
#  executed_at      :datetime
#  machine          :string(255)
#  operations       :text(65535)
#  platform         :integer          not null
#  status           :integer          default("pending")
#  task_uuid        :string(255)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  browser_id       :bigint
#
# Indexes
#
#  index_warmup_tasks_on_account_id             (account_id)
#  index_warmup_tasks_on_account_id_and_status  (account_id,status)
#  index_warmup_tasks_on_browser_id             (browser_id)
#  index_warmup_tasks_on_executed_at            (executed_at)
#  index_warmup_tasks_on_machine                (machine)
#  index_warmup_tasks_on_platform               (platform)
#  index_warmup_tasks_on_task_uuid              (task_uuid)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (browser_id => browsers.id)
#

class WarmupTask < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :browser, optional: true

  before_validation :generate_task_uuid, on: :create

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
