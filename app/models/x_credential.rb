# == Schema Information
#
# Table name: x_account_credentials
#
#  id                     :bigint           not null, primary key
#  account_id             :bigint           not null
#  x_user_id              :string(255)
#  access_token_encrypted :text(65535)
#  refresh_token_encrypted: text(65535)
#  token_expires_at       :datetime
#  scope                  :string(255)
#  auth_status            :integer          default("pending"), not null
#  code_verifier          :string(255)
#  state                  :string(255)
#  authorized_at          :datetime
#  last_refreshed_at      :datetime
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#
# Indexes
#
#  index_x_account_credentials_on_account_id (account_id) UNIQUE
#  index_x_account_credentials_on_x_user_id  (x_user_id)
#
# X（Twitter）API 认证凭证模型。
#
# 记录本系统 twitter 账号在 X 平台 OAuth 2.0（Authorization Code + PKCE）授权后的凭证。
# access_token / refresh_token 是账号级敏感凭证，用 MessageEncryptor 加密存储（不落明文）。
# 授权流程（与 postforme 同构）：
#   生成 PKCE → 构造授权 URL → 下发机器端打开 → 用户授权 → 机器端截 code 回调 →
#   用 code + code_verifier 换 access/refresh token → 加密存凭证 → 清除 code_verifier。
class XCredential < ApplicationRecord
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
