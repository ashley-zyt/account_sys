# postforme 授权流程编排。
#
# 授权是一次性异步流程：
#   1. 调 postforme 拿授权 URL（带 external_id = 本系统账号 ID）
#   2. 记录「授权中」，下发机器端让指纹浏览器打开授权页
#   3. 人工在浏览器完成 OAuth
#   4. 轮询 postforme 按 external_id 反查，拿到 social_account_id 后标记「已授权」
module PostformeAuthService
  # 发起授权：拿授权 URL → 记录「授权中」→ 下发机器端打开授权页。
  # @return [Hash] { success:, message:, auth_url: }
  def self.start_authorization(account)
    return { success: false, message: '账号未绑定指纹浏览器，无法授权' } if account.browser.blank?

    resp = PostformeApi.auth_url(platform: account.platform, external_id: account.id.to_s)
    return { success: false, message: "获取授权 URL 失败：#{resp[:raw]}" } unless resp[:code] == 200

    url = resp[:body]['url'].to_s
    return { success: false, message: 'postforme 未返回授权 URL' } if url.blank?

    # 记录授权中
    pa = account.postforme_account || account.create_postforme_account
    pa.update!(auth_status: :authorizing, social_account_id: nil, authorized_at: nil)

    # 下发机器端：指纹浏览器打开授权页（机器端 open_auth_url 接口，需机器端先行支持）
    machine_ip = account.browser.machine_ip
    if machine_ip.blank?
      Rails.logger.warn "[PostformeAuth] 账号 #{account.id} 浏览器未设 machine_ip，跳过下发打开授权页（授权 URL 需人工打开）"
    else
      payload = {
        profile_name: account.browser.profile_name,
        url: url,
        wait_seconds: 600,
        async: true,
        ref: "PostformeAuth:#{account.id}"
      }
      RemoteApiClient.post("https://#{machine_ip}/accounts/open_auth_url", payload, read_timeout: 30)
    end

    { success: true, message: '已发起授权，请在浏览器完成 OAuth', auth_url: url }
  end

  # 轮询授权结果：查 postforme 按 external_id 反查，拿到 social_account_id 则标记「已授权」。
  # @return [Hash, nil] 授权成功返回 { success: true, social_account_id: }，否则 nil
  def self.check_authorization(account)
    pa = account.postforme_account
    return nil unless pa && pa.authorizing?

    resp = PostformeApi.social_accounts(external_id: account.id.to_s)
    return nil unless resp[:code] == 200

    connected = Array(resp[:body]).find { |a| a['status'] == 'connected' && a['id'].present? }
    return nil unless connected

    pa.update!(auth_status: :authorized, social_account_id: connected['id'], authorized_at: Time.current)
    { success: true, social_account_id: connected['id'] }
  end

  # 确认授权结果（机器端点击授权按钮后的回调入口）。
  # 优先用机器端带回的 social_account_id；没有则主动查 postforme 反查。
  # @param account [Account] 本系统账号
  # @param social_account_id [String, nil] 机器端带回的 postforme 社交账号 ID（可选）
  # @return [Hash, nil] 授权成功返回 { success: true, social_account_id: }，否则 nil
  def self.confirm_authorization(account, social_account_id: nil)
    pa = account.postforme_account
    return nil unless pa && pa.authorizing?

    sid = social_account_id.to_s.strip.presence
    if sid.blank?
      return check_authorization(account)
    end

    pa.update!(auth_status: :authorized, social_account_id: sid, authorized_at: Time.current)
    { success: true, social_account_id: sid }
  end
end
