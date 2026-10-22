# 客户托管账号的 X（Twitter）授权流程编排（独立于自有账号，不做机器端动作）。
#
# 认证是纯手动流程（PKCE + Authorization Code）：
#   1. 生成 PKCE + 构造授权 URL，回写 x_account_credentials（hosting_account_id）标记 authorizing
#   2. 人工打开授权 URL 完成 OAuth，浏览器跳转 localhost?code=xxx
#   3. 人工从地址栏抠出 code 提交，用 code + code_verifier 换 token，标记 authorized
module HostingXAuthService
  # 「认证中」超过此时长视为卡死，允许重新发起（覆盖旧 code_verifier/state）。
  STALE_AUTHORIZING_THRESHOLD = 30.minutes

  # 发起认证：生成 PKCE → 记录「认证中」。
  # @return [Hash] { success:, message:, auth_url: }
  def self.start_authorization(hosting_account, force: false)
    return { success: false, message: 'X API 未配置（请在 .env 设置 X_CLIENT_ID / X_CLIENT_SECRET）' } unless XApi.configured?

    xc = hosting_account.x_credential
    if xc&.authorizing? && xc.code_verifier.present?
      stale = xc.updated_at.present? && xc.updated_at <= STALE_AUTHORIZING_THRESHOLD.ago
      if !force && !stale
        return { success: false, message: '该账号已有进行中的认证，请勿重复发起' }
      end
    end

    verifier, challenge = XApi.generate_pkce
    state = SecureRandom.urlsafe_base64(16)

    url = XApi.authorization_url(state: state, code_challenge: challenge)

    xc ||= hosting_account.create_x_credential
    xc.update!(auth_status: :authorizing, code_verifier: verifier, state: state, authorized_at: nil)

    Rails.logger.info "[HostingXAuth] 托管账号 #{hosting_account.id} 发起认证: state=#{state} verifier_len=#{verifier.length} at=#{Time.current}"

    { success: true, message: '已发起认证，请在浏览器完成授权', auth_url: url }
  end

  # 完成认证：用 code + code_verifier 换 token 存凭证。
  def self.complete_authorization(hosting_account, code:, state: nil)
    xc = hosting_account.x_credential
    return { success: false, message: '该账号未发起认证，无法完成' } if xc.nil?
    return { success: false, message: '该账号上次认证失败，请重新发起认证' } if xc.failed?
    return { success: false, message: '该账号未发起认证，无法完成' } unless xc.authorizing?

    if state.present? && xc.state.present? && state != xc.state
      return { success: false, message: 'state 不匹配，拒绝换 token' }
    end

    verifier = xc.code_verifier
    if verifier.blank?
      xc.update!(auth_status: :failed)
      return { success: false, message: '缺少 PKCE code_verifier，请重新发起认证' }
    end

    resp = XApi.exchange_code(code: code, code_verifier: verifier)
    unless XApi.success?(resp)
      xc.update!(auth_status: :failed)
      return { success: false, message: "换取 token 失败：#{resp[:raw].to_s.truncate(200)}" }
    end

    body = resp[:body]
    access_token = body['access_token'].to_s
    if access_token.blank?
      xc.update!(auth_status: :failed)
      return { success: false, message: 'X 未返回 access_token' }
    end

    expires_in = body['expires_in'].to_i
    xc.update!(
      auth_status: :authorized,
      access_token: access_token,
      refresh_token: body['refresh_token'].to_s.presence,
      token_expires_at: expires_in > 0 ? Time.current + expires_in.seconds : nil,
      scope: body['scope'].to_s.presence,
      code_verifier: nil,
      state: nil,
      authorized_at: Time.current,
      last_refreshed_at: Time.current
    )

    { success: true, message: '认证成功', x_user_id: xc.x_user_id }
  end
end
