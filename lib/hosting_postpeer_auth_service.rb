# 客户托管账号的 postpeer 授权流程编排（独立于自有账号，不做机器端动作）。
#
# 授权是纯手动流程：
#   1. 创建 postpeer profile
#   2. 拿授权 URL
#   3. 回写 postpeer_accounts（hosting_account_id）标记 authorizing
#   4. 人工打开授权 URL 完成 OAuth
#   5. 确认授权 → 反查 accountId → 标记 authorized
module HostingPostpeerAuthService
  SUPPORTED_PLATFORMS = %w[facebook instagram youtube tiktok].freeze

  # 发起授权：建 profile → 拿授权 URL → 记录「授权中」。
  # @return [Hash] { success:, message:, auth_url: }
  def self.start_authorization(hosting_account)
    unless SUPPORTED_PLATFORMS.include?(hosting_account.platform.to_s)
      return { success: false, message: 'postpeer 不支持该平台（仅 facebook/instagram/youtube/tiktok）' }
    end

    pa = hosting_account.postpeer_account || hosting_account.create_postpeer_account

    profile_id = pa.profile_id
    if profile_id.blank?
      resp = PostpeerApi.create_profile(name: "hosting_#{hosting_account.id}")
      unless PostpeerApi.success?(resp)
        return { success: false, message: "创建 postpeer profile 失败：#{resp[:raw]}" }
      end
      profile_id = resp[:body].is_a?(Hash) ? resp[:body].dig('profile', 'id').to_s : ''
      return { success: false, message: "postpeer 未返回 profile ID：#{resp[:raw]}" } if profile_id.blank?
    end

    resp = PostpeerApi.connect_url(platform: hosting_account.platform, profile_id: profile_id)
    url = resp[:body].is_a?(Hash) ? resp[:body]['url'].to_s : ''
    return { success: false, message: "获取授权 URL 失败：#{resp[:raw]}" } if url.blank?

    pa.update!(auth_status: :authorizing, peer_account_id: nil, authorized_at: nil, profile_id: profile_id)

    { success: true, message: '已生成授权链接，请人工完成 OAuth', auth_url: url }
  end

  # 轮询授权结果：查 postpeer 按 profileId 反查集成，拿到 accountId 则标记「已授权」。
  def self.check_authorization(hosting_account)
    pa = hosting_account.postpeer_account
    return nil unless pa && pa.authorizing?
    return nil if pa.profile_id.blank?

    resp = PostpeerApi.integrations(profile_id: pa.profile_id)
    return nil unless PostpeerApi.success?(resp)

    integration = PostpeerApi.integration_items(resp).first
    return nil unless integration && integration['id'].present?

    pa.update!(auth_status: :authorized, peer_account_id: integration['id'], authorized_at: Time.current)
    { success: true, peer_account_id: integration['id'] }
  end

  # 确认授权结果（人工完成 OAuth 后提交确认）。
  # 优先用提交的 accountId；没有则主动查 postpeer 反查。
  def self.confirm_authorization(hosting_account, peer_account_id: nil)
    pa = hosting_account.postpeer_account
    return nil unless pa && pa.authorizing?

    sid = peer_account_id.to_s.strip.presence
    if sid.blank?
      return check_authorization(hosting_account)
    end

    pa.update!(auth_status: :authorized, peer_account_id: sid, authorized_at: Time.current)
    { success: true, peer_account_id: sid }
  end
end
