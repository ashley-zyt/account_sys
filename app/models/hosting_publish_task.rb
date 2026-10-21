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
