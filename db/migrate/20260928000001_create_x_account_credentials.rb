# 建 X（Twitter）API 认证凭证表。
#
# 记录本系统 twitter 账号在 X 平台 OAuth 2.0 授权后的凭证：
#   - access_token / refresh_token 加密存储（AES-256-GCM，基于 secret_key_base）
#   - access_token 约 2 小时过期，需用 refresh_token 刷新
#   - code_verifier / state 是授权流程的临时值，换完 token 后清除
class CreateXAccountCredentials < ActiveRecord::Migration[6.1]
  def change
    create_table :x_account_credentials do |t|
      t.bigint    :account_id, null: false, comment: '本系统账号 ID（一对一）'
      t.string    :x_user_id, comment: 'X 平台 user id'
      t.text      :access_token_encrypted, comment: '加密后的 access_token'
      t.text      :refresh_token_encrypted, comment: '加密后的 refresh_token'
      t.datetime  :token_expires_at, comment: 'access_token 过期时间'
      t.string    :scope, comment: '授权范围（逗号分隔）'
      t.integer   :auth_status, default: 0, null: false, comment: '认证状态 0未认证 1认证中 2已认证 3失败'
      t.string    :code_verifier, comment: 'PKCE code_verifier（授权流程临时值，换完 token 清除）'
      t.string    :state, comment: '防 CSRF 随机串（临时）'
      t.datetime  :authorized_at, comment: '认证完成时间'
      t.datetime  :last_refreshed_at, comment: '最近刷新 token 时间'
      t.timestamps
    end

    add_index :x_account_credentials, :account_id, unique: true
    add_index :x_account_credentials, :x_user_id
  end
end
