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

  def reset_to_pending!
    update!(
      account_id: nil,
      browser_id: nil,
      status: :pending,
      start_at: nil
    )
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme video_url status templete_id video_text account_id browser_id error_msg start_at actual_publish_time task_uuid platform title description created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account browser]
  end

  private

  def generate_task_uuid
    self.task_uuid ||= "HG-#{SecureRandom.uuid}"
  end
end