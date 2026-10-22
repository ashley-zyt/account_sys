# 客户托管账号的 postforme 授权流程编排（独立于自有账号，不做机器端动作）。
#
# 授权是纯手动流程：
#   1. 拿授权 URL（external_id = "hosting_<id>"，与自有账号的 account.id 区分）
#   2. 回写 postforme_accounts（hosting_account_id）标记 authorizing
#   3. 人工打开授权 URL 完成 OAuth
#   4. 确认授权 → 反查 social_account_id → 标记 authorized
module HostingPostformeAuthService
  SUPPORTED_PLATFORMS = %w[facebook instagram youtube tiktok].freeze

  # 发起授权：拿授权 URL → 记录「授权中」。
  # @return [Hash] { success:, message:, auth_url: }
  def self.start_authorization(hosting_account)
    unless SUPPORTED_PLATFORMS.include?(hosting_account.platform.to_s)
      return { success: false, message: 'postforme 不支持该平台（仅 facebook/instagram/youtube/tiktok）' }
    end

    pa = hosting_account.postforme_account || hosting_account.create_postforme_account

    resp = PostformeApi.auth_url(platform: hosting_account.platform, external_id: external_id_for(hosting_account))
    url = resp[:body].is_a?(Hash) ? resp[:body]['url'].to_s : ''
    return { success: false, message: "获取授权 URL 失败：#{resp[:raw]}" } if url.blank?

    pa.update!(auth_status: :authorizing, social_account_id: nil, authorized_at: nil)

    { success: true, message: '已生成授权链接，请人工完成 OAuth', auth_url: url }
  end

  # 轮询授权结果：查 postforme 按 external_id 反查，拿到 social_account_id 则标记「已授权」。
  def self.check_authorization(hosting_account)
    pa = hosting_account.postforme_account
    return nil unless pa && pa.authorizing?

    resp = PostformeApi.social_accounts(external_id: external_id_for(hosting_account))
    return nil unless PostformeApi.success?(resp)

    connected = PostformeApi.items(resp).find { |a| a['status'] == 'connected' && a['id'].present? }
    return nil unless connected

    pa.update!(auth_status: :authorized, social_account_id: connected['id'], authorized_at: Time.current)
    { success: true, social_account_id: connected['id'] }
  end

  # 确认授权结果（人工完成 OAuth 后提交确认）。
  # 优先用提交的 social_account_id；没有则主动查 postforme 反查。
  def self.confirm_authorization(hosting_account, social_account_id: nil)
    pa = hosting_account.postforme_account
    return nil unless pa && pa.authorizing?

    sid = social_account_id.to_s.strip.presence
    if sid.blank?
      return check_authorization(hosting_account)
    end

    pa.update!(auth_status: :authorized, social_account_id: sid, authorized_at: Time.current)
    { success: true, social_account_id: sid }
  end

  # 托管账号在 postforme 侧的 external_id（带前缀，避免与自有账号 account.id 冲突）
  def self.external_id_for(hosting_account)
    "hosting_#{hosting_account.id}"
  end
end
