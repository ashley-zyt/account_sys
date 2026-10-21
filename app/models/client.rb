# == Schema Information
#
# Table name: clients
#
#  id                               :bigint           not null, primary key
#  contact(联系人)                  :string(255)
#  contact_info(联系方式)           :string(255)
#  name(客户名称)                   :string(255)      not null
#  remark(备注)                     :text(65535)
#  status(状态 0合作中 1暂停 2终止) :integer          default("active"), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#
# Indexes
#
#  index_clients_on_name  (name) UNIQUE
#
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
