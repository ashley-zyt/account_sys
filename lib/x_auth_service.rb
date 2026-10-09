# X（Twitter）API 认证编排。
#
# 认证是一次性异步流程（与 postforme 授权同构）：
#   1. 生成 PKCE + 构造授权 URL（redirect_uri 指向 localhost）
#   2. 记录「认证中」，存 code_verifier/state，下发机器端让指纹浏览器打开授权页
#   3. 人工在浏览器完成授权，浏览器跳转 localhost?code=xxx
#   4. 机器端检测跳转、从 URL 抠 code，主动 POST 回调 account_sys
#   5. 用 code + code_verifier 换 access/refresh token，加密存凭证，清除 code_verifier
module XAuthService
  # 「认证中」超过此时长视为卡死，允许重新发起（覆盖旧 code_verifier/state）。
  # 否则默认不覆盖，避免旧授权页的 code 撞上新 verifier/state 导致 state 不匹配 / code 无效。
  STALE_AUTHORIZING_THRESHOLD = 30.minutes

  # 发起认证：生成 PKCE → 记录「认证中」→ 下发机器端打开授权页。
  # @param force [Boolean] 强制重新发起（覆盖进行中的认证）。默认 false，防重复触发。
  # @return [Hash] { success:, message:, auth_url: }
  def self.start_authorization(account, force: false)
    return { success: false, message: '账号未绑定指纹浏览器，无法认证' } if account.browser.blank?
    return { success: false, message: 'X API 未配置（请在 .env 设置 X_CLIENT_ID / X_CLIENT_SECRET）' } unless XApi.configured?

    # 防重复：已有「认证中」且未完成时，默认不覆盖 code_verifier/state，
    # 否则旧授权页的 code 会撞上新 verifier/state，导致 state 不匹配 / code 无效。
    # 仅当「卡死」（authorizing 超过 STALE_AUTHORIZING_THRESHOLD）或显式 force 时才覆盖。
    xc = account.x_credential
    if xc&.authorizing? && xc.code_verifier.present?
      stale = xc.updated_at.present? && xc.updated_at <= STALE_AUTHORIZING_THRESHOLD.ago
      if !force && !stale
        return { success: false, message: '该账号已有进行中的认证，请勿重复发起' }
      end
    end

    verifier, challenge = XApi.generate_pkce
    state = SecureRandom.urlsafe_base64(16)

    url = XApi.authorization_url(state: state, code_challenge: challenge)

    xc ||= account.create_x_credential
    xc.update!(auth_status: :authorizing, code_verifier: verifier, state: state, authorized_at: nil)

    # 诊断：记录发起认证的时间/state/verifier 长度，便于与后续回调失败日志对应排查
    Rails.logger.info "[XAuth] 账号 #{account.id} 发起认证: state=#{state} verifier_len=#{verifier.length} at=#{Time.current}"

    # 下发机器端：指纹浏览器打开授权页（复用 open_auth_url，机器端需扩展「检测跳转截 code」）
    machine_ip = account.browser.machine_ip
    if machine_ip.blank?
      Rails.logger.warn "[XAuth] 账号 #{account.id} 浏览器未设 machine_ip，跳过下发打开授权页（授权 URL 需人工打开）"
    else
      payload = {
        profile_name: account.browser.profile_name,
        url: url,
        wait_seconds: 600,
        async: true,
        ref: "XAuth:#{account.id}"
      }
      RemoteApiClient.post("https://#{machine_ip}/accounts/open_auth_url", payload, read_timeout: 30)
    end

    { success: true, message: '已发起认证，请在浏览器完成授权', auth_url: url }
  end

  # 完成认证：机器端截到 code 回调后，用 code + code_verifier 换 token 存凭证。
  # @param code [String] X 授权完成后回传的授权码
  # @param state [String, nil] 机器端若带回 state 则校验（防 CSRF）
  # @return [Hash] { success:, message:, x_user_id: }
  def self.complete_authorization(account, code:, state: nil)
    xc = account.x_credential
    if xc.nil?
      return { success: false, message: '该账号未发起认证，无法完成' }
    end
    if xc.failed?
      return { success: false, message: '该账号上次认证失败（换取 token 未成功），请重新发起认证' }
    end
    return { success: false, message: '该账号未发起认证，无法完成' } unless xc.authorizing?

    # 防 CSRF：state 若带回就校验（机器端可能拿不到 state，此时放宽、仍继续）
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
      # 把 X 返回的原始错误完整打日志，便于定位是 invalid_grant / invalid_client / redirect_uri 不匹配等。
      # 附带 code 长度/verifier 长度/state 对照/凭证更新时间，便于判断「code 被机器端截断」还是「verifier 被覆盖」。
      Rails.logger.error "[XAuth] 账号 #{account.id} 换 token 失败: code=#{resp[:code]} body=#{resp[:raw].to_s.truncate(500)} code_len=#{code.to_s.length} verifier_len=#{verifier.to_s.length} state_cb=#{state.inspect} state_db=#{xc.state.inspect} xc_updated_at=#{xc.updated_at}"
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
    token_expires_at = expires_in > 0 ? Time.current + expires_in.seconds : nil
    refresh_token = body['refresh_token'].to_s

    xc.update!(
      auth_status: :authorized,
      access_token: access_token,
      refresh_token: refresh_token.presence,
      token_expires_at: token_expires_at,
      scope: body['scope'].to_s.presence,
      code_verifier: nil,
      state: nil,
      authorized_at: Time.current,
      last_refreshed_at: Time.current
    )

    # 顺手拿 x_user_id（后续 DM/评论定位用；失败不影响认证成功）
    fetch_x_user_id(account)

    { success: true, message: '认证成功', x_user_id: xc.reload.x_user_id }
  end

  # 刷新 access_token（供定时任务 / 调用前检查用）。
  # @return [Hash] { success:, message: }
  def self.refresh_access_token(account)
    xc = account.x_credential
    return { success: false, message: '该账号未认证' } unless xc && xc.authorized?

    rt = xc.refresh_token
    if rt.blank?
      xc.update!(auth_status: :failed)
      return { success: false, message: '无 refresh_token，需重新认证' }
    end

    resp = XApi.refresh(refresh_token: rt)
    unless XApi.success?(resp)
      # refresh_token 失效（用户撤销授权等）→ 标记需重新认证
      xc.update!(auth_status: :failed)
      return { success: false, message: "刷新 token 失败：#{resp[:raw].to_s.truncate(200)}" }
    end

    body = resp[:body]
    access_token = body['access_token'].to_s
    return { success: false, message: 'X 未返回新 access_token' } if access_token.blank?

    expires_in = body['expires_in'].to_i
    xc.update!(
      access_token: access_token,
      refresh_token: body['refresh_token'].presence || rt,
      token_expires_at: expires_in > 0 ? Time.current + expires_in.seconds : nil,
      last_refreshed_at: Time.current
    )
    { success: true, message: '已刷新 access_token' }
  end

  # 获取该账号当前有效的 access_token（过期则先刷新），供后续 DM/评论接口用。
  # @return [String, nil] 有效 access_token；未认证或刷新失败返回 nil
  def self.access_token_for(account)
    xc = account.x_credential
    return nil unless xc && xc.authorized?

    if xc.access_token_expired?
      refresh_access_token(account)
      xc = account.x_credential.reload
      return nil unless xc.authorized?
    end

    xc.access_token
  end

  # 从 /2/users/me 拿 x_user_id 写回（best effort，失败不抛）。
  def self.fetch_x_user_id(account)
    token = access_token_for(account)
    return if token.blank?

    resp = XApi.me(access_token: token)
    return unless XApi.success?(resp)

    data = resp[:body]['data']
    if data.is_a?(Hash) && data['id'].present?
      account.x_credential.update!(x_user_id: data['id'].to_s)
    end
  rescue => e
    Rails.logger.error "[XAuth] 获取 x_user_id 失败: #{e.message}"
  end

  # 刷新所有已认证账号中快过期的 access_token（供定时任务调用）。
  # @return [Hash] { refreshed:, failed: }
  def self.refresh_all
    refreshed = 0
    failed = 0
    XCredential.where(auth_status: :authorized).find_each do |xc|
      next unless xc.access_token_expired?
      result = refresh_access_token(xc.account)
      result[:success] ? refreshed += 1 : failed += 1
    end
    Rails.logger.info "[XAuth] token 刷新完成：成功 #{refreshed}，失败 #{failed}"
    { refreshed: refreshed, failed: failed }
  end
end
