# == Schema Information
#
# Table name: hosting_publish_tasks
#
#  id                                                 :bigint           not null, primary key
#  error_msg(失败原因)                                :text(65535)
#  executed_at(执行时间)                              :datetime
#  platform(目标平台)                                 :string(255)
#  publish_channel(发布渠道)                          :string(255)
#  resource_type(资源队列成品多态类型（如 MoveTask）) :string(255)
#  status(状态 0待发布 1执行中 2成功 3失败)           :integer          default("pending"), not null
#  theme(主题)                                        :string(255)
#  created_at                                         :datetime         not null
#  updated_at                                         :datetime         not null
#  client_id(归属客户)                                :bigint           not null
#  hosting_account_id(托管账号)                       :bigint           not null
#  resource_id(资源队列成品多态 ID)                   :bigint
#
# Indexes
#
#  index_hosting_publish_tasks_on_client_id                      (client_id)
#  index_hosting_publish_tasks_on_hosting_account_id             (hosting_account_id)
#  index_hosting_publish_tasks_on_resource_type_and_resource_id  (resource_type,resource_id) UNIQUE
#  index_hosting_publish_tasks_on_status                         (status)
#
# Foreign Keys
#
#  fk_rails_...  (client_id => clients.id)
#  fk_rails_...  (hosting_account_id => hosting_accounts.id)
#
class HostingPublishTask < ApplicationRecord
  belongs_to :hosting_account
  belongs_to :client
  belongs_to :resource, polymorphic: true, optional: true

  enum status: { pending: 0, executing: 1, success: 2, failed: 3 }

  def self.ransackable_attributes(auth_object = nil)
    %w[id resource_type resource_id platform theme hosting_account_id client_id publish_channel status error_msg executed_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[hosting_account client resource]
  end
end
