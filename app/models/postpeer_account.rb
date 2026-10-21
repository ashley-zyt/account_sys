# == Schema Information
#
# Table name: postpeer_accounts
#
#  id                                                                    :bigint           not null, primary key
#  auth_status(授权状态 0未授权 1授权中 2已授权 3失败)                   :integer          default("pending"), not null
#  authorized_at(授权完成时间)                                           :datetime
#  created_at                                                            :datetime         not null
#  updated_at                                                            :datetime         not null
#  account_id(本系统账号 ID（一对一）)                                   :bigint
#  hosting_account_id                                                    :bigint
#  peer_account_id(postpeer 集成 ID（accountId，发布时用）)              :string(255)
#  profile_id(postpeer profile ID（授权时隔离账号，用于反查 accountId）) :string(255)
#
# Indexes
#
#  index_postpeer_accounts_on_account_id          (account_id) UNIQUE
#  index_postpeer_accounts_on_hosting_account_id  (hosting_account_id) UNIQUE
#  index_postpeer_accounts_on_peer_account_id     (peer_account_id)
#
# Foreign Keys
#
#  fk_rails_...  (hosting_account_id => hosting_accounts.id)
#
class PostpeerAccount < ApplicationRecord
  belongs_to :account, optional: true
  belongs_to :hosting_account, optional: true

  # 授权状态：pending=未授权 / authorizing=授权中 / authorized=已授权 / failed=失败
  enum auth_status: {
    pending: 0,
    authorizing: 1,
    authorized: 2,
    failed: 3
  }

  # 是否已成功授权（授权完成且已拿到 peer_account_id）
  def authorized?
    auth_status == "authorized" && peer_account_id.present?
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id account_id profile_id peer_account_id auth_status authorized_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account hosting_account]
  end
end
