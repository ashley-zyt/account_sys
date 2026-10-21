class HostingAccount < ApplicationRecord
  belongs_to :client
  has_many :hosting_publish_tasks, dependent: :destroy

  enum status: { active: 0, paused: 1, terminated: 2 }

  validates :client_id, presence: true
  validates :platform, presence: true

  # 该托管账号指定的资源队列对应的 WorkMode（resource_queue 存 WorkMode key）
  def work_mode
    WorkMode.find(resource_queue)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id client_id platform theme resource_queue publish_channel status remark created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[client hosting_publish_tasks]
  end
end
