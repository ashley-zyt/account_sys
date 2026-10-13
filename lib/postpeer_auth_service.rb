# postpeer 授权流程编排。
#
# 授权是一次性异步流程：
#   1. 创建 profile（postpeer 用 profileId 隔离账号，授权后按 profileId 反查 accountId）
#   2. 调 postpeer 拿授权 URL（绑定 profileId）
#   3. 记录「授权中」，下发机器端让指纹浏览器打开授权页
#   4. 人工在浏览器完成 OAuth
#   5. 轮询 postpeer 按 profileId 反查集成，拿到 accountId 后标记「已授权」
#
# 注意：postpeer 发布 X（twitter）会消耗积分，本模块仅支持 facebook/instagram/youtube/tiktok，
# twitter 账号不走 postpeer。
module PostpeerAuthService
  SUPPORTED_PLATFORMS = %w[facebook instagram youtube tiktok].freeze

  # 发起授权：建 profile → 拿授权 URL → 记录「授权中」→ 下发机器端打开授权页。
  # @param skip_machine [Boolean] true 时跳过机器端下发（全手动流程：仅生成授权链接）
  # @return [Hash] { success:, message:, auth_url: }
  def self.start_authorization(account, skip_machine: false)
    return { success: false, message: 'postpeer 不支持该平台（仅 facebook/instagram/youtube/tiktok）' } unless SUPPORTED_PLATFORMS.include?(account.platform.to_s)
    return { success: false, message: '账号未绑定指纹浏览器，无法授权' } if account.browser.blank?

    pa = account.postpeer_account || account.create_postpeer_account

    # 确保有 profile（授权后按 profileId 反查 accountId）
    profile_id = pa.profile_id
    if profile_id.blank?
      resp = PostpeerApi.create_profile(name: account.id.to_s)
      unless PostpeerApi.success?(resp)
        return { success: false, message: "创建 postpeer profile 失败：#{resp[:raw]}" }
      end
      profile_id = resp[:body].is_a?(Hash) ? resp[:body].dig('profile', 'id').to_s : ''
      return { success: false, message: "postpeer 未返回 profile ID：#{resp[:raw]}" } if profile_id.blank?
    end

    resp = PostpeerApi.connect_url(platform: account.platform, profile_id: profile_id)
    url = resp[:body].is_a?(Hash) ? resp[:body]['url'].to_s : ''
    return { success: false, message: "获取授权 URL 失败：#{resp[:raw]}" } if url.blank?

    pa.update!(auth_status: :authorizing, peer_account_id: nil, authorized_at: nil, profile_id: profile_id)

    unless skip_machine
      machine_ip = account.browser.machine_ip
      if machine_ip.blank?
        Rails.logger.warn "[PostpeerAuth] 账号 #{account.id} 浏览器未设 machine_ip，跳过下发打开授权页（授权 URL 需人工打开）"
      else
        payload = {
          profile_name: account.browser.profile_name,
          url: url,
          wait_seconds: 600,
          async: true,
          ref: "PostpeerAuth:#{account.id}"
        }
        RemoteApiClient.post("https://#{machine_ip}/accounts/open_auth_url", payload, read_timeout: 30)
      end
    end

    { success: true, message: '已发起授权，请在浏览器完成 OAuth', auth_url: url }
  end

  # 轮询授权结果：查 postpeer 按 profileId 反查集成，拿到 accountId 则标记「已授权」。
  # @return [Hash, nil] 授权成功返回 { success: true, peer_account_id: }，否则 nil
  def self.check_authorization(account)
    pa = account.postpeer_account
    return nil unless pa && pa.authorizing?
    return nil if pa.profile_id.blank?

    resp = PostpeerApi.integrations(profile_id: pa.profile_id)
    return nil unless PostpeerApi.success?(resp)

    integration = PostpeerApi.integration_items(resp).first
    return nil unless integration && integration['id'].present?

    pa.update!(auth_status: :authorized, peer_account_id: integration['id'], authorized_at: Time.current)
    { success: true, peer_account_id: integration['id'] }
  end

  # 确认授权结果（机器端点击授权按钮后的回调入口）。
  # 优先用机器端带回的 accountId；没有则主动查 postpeer 反查。
  def self.confirm_authorization(account, peer_account_id: nil)
    pa = account.postpeer_account
    return nil unless pa && pa.authorizing?

    sid = peer_account_id.to_s.strip.presence
    if sid.blank?
      return check_authorization(account)
    end

    pa.update!(auth_status: :authorized, peer_account_id: sid, authorized_at: Time.current)
    { success: true, peer_account_id: sid }
  end
end
