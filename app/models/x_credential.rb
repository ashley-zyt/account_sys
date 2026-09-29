# == Schema Information
#
# Table name: x_account_credentials
#
#  id                                                                   :bigint           not null, primary key
#  access_token_encrypted(加密后的 access_token)                        :text(65535)
#  auth_status(认证状态 0未认证 1认证中 2已认证 3失败)                  :integer          default("pending"), not null
#  authorized_at(认证完成时间)                                          :datetime
#  code_verifier(PKCE code_verifier（授权流程临时值，换完 token 清除）) :string(255)
#  last_refreshed_at(最近刷新 token 时间)                               :datetime
#  refresh_token_encrypted(加密后的 refresh_token)                      :text(65535)
#  scope(授权范围（逗号分隔）)                                          :string(255)
#  state(防 CSRF 随机串（临时）)                                        :string(255)
#  token_expires_at(access_token 过期时间)                              :datetime
#  created_at                                                           :datetime         not null
#  updated_at                                                           :datetime         not null
#  account_id(本系统账号 ID（一对一）)                                  :bigint           not null
#  x_user_id(X 平台 user id)                                            :string(255)
#
# Indexes
#
#  index_x_account_credentials_on_account_id  (account_id) UNIQUE
#  index_x_account_credentials_on_x_user_id   (x_user_id)
#
class XCredential < ApplicationRecord
  # 显式指定表名，避免 Rails 按类名默认推导成 x_credentials（迁移实际建的是 x_account_credentials）
  self.table_name = "x_account_credentials"

  belongs_to :account

  # 认证状态：pending=未认证 / authorizing=认证中 / authorized=已认证 / failed=失败
  enum auth_status: {
    pending: 0,
    authorizing: 1,
    authorized: 2,
    failed: 3
  }

  # 加密器：基于 secret_key_base 的 AES-256-GCM 对称加密（无额外 gem）。
  def self.encryptor
    @encryptor ||= ActiveSupport::MessageEncryptor.new(Rails.application.secret_key_base[0, 32])
  end

  # access_token 的加解密（对外的 access_token 是明文，库里存 access_token_encrypted）
  def access_token
    return nil if access_token_encrypted.blank?
    self.class.encryptor.decrypt_and_verify(access_token_encrypted)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def access_token=(value)
    self.access_token_encrypted = value.present? ? self.class.encryptor.encrypt_and_sign(value) : nil
  end

  def refresh_token
    return nil if refresh_token_encrypted.blank?
    self.class.encryptor.decrypt_and_verify(refresh_token_encrypted)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def refresh_token=(value)
    self.refresh_token_encrypted = value.present? ? self.class.encryptor.encrypt_and_sign(value) : nil
  end

  # 是否已成功认证（状态已认证 且 access_token 可解密）
  def authorized?
    auth_status == "authorized" && access_token.present?
  end

  # access_token 是否已过期（或临近过期，留 5 分钟缓冲）
  def access_token_expired?
    token_expires_at.blank? || token_expires_at <= 5.minutes.from_now
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id account_id x_user_id auth_status authorized_at last_refreshed_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account]
  end
end
