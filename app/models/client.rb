class Client < ApplicationRecord
  has_many :hosting_accounts, dependent: :restrict_with_error
  has_many :hosting_publish_tasks, dependent: :restrict_with_error

  enum status: { active: 0, paused: 1, terminated: 2 }

  validates :name, presence: true, uniqueness: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id name contact contact_info status remark created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[hosting_accounts hosting_publish_tasks]
  end
end
