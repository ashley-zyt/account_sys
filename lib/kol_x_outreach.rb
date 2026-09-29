# X API 触达适配器（KOL twitter 私信 / 查回复走 X API 的通道）。
#
# 与 KolOutreachApi（机器端指纹浏览器）并列，是 KOL 触达的 X API 通道。
# X API 是同步的：发私信立即返回结果、拉消息主动拉取，无需机器端回调、无 async。
#
# 状态流转复用 KolOutreachApi.apply_send_result / apply_reply_result（同步路径），
# 保证与机器端通道的 KolMessage / KolContact / Kol 状态机一致。
class KolXOutreach
  class << self
    # 发私信（同步）
    # @return [Hash] { success:, reason:, error: }
    #   reason 取值：account_risk（token 失效/未认证，需重新授权，会休眠账号）
    #               dm_refused（对方拒绝/不接受私信，应停用该联系方式）
    #               target_invalid（对方 @username 无效/用户不存在）
    #               x_api_error（其它 X 侧错误）
    def send_message(account:, contact:, content:, message_id: nil)
      token = XAuthService.access_token_for(account)
      return { success: false, reason: 'account_risk', error: '账号未完成 X 认证或无有效 token' } if token.blank?

      participant_id = resolve_participant_id(account, contact)
      return { success: false, reason: 'target_invalid', error: '无法解析对方 X user_id（@username 无效或用户不存在）' } if participant_id.blank?

      resp = XApi.send_dm(access_token: token, participant_id: participant_id, text: content)
      if XApi.success?(resp)
        { success: true }
      else
        { success: false, reason: classify_failure(resp), error: extract_error(resp) }
      end
    end

    # 查回复（同步）：拉 1-1 会话最新 DM 事件，过滤出「对方发来的 MessageCreate」。
    # @return [Hash] { has_reply:, replies: [{ 'content'=>, 'observed_at'=> }, ...] }
    def fetch_replies(account:, contact:)
      token = XAuthService.access_token_for(account)
      return { has_reply: false, replies: [] } if token.blank?

      participant_id = resolve_participant_id(account, contact)
      return { has_reply: false, replies: [] } if participant_id.blank?

      resp = XApi.dm_events(access_token: token, participant_id: participant_id, max_results: 100)
      return { has_reply: false, replies: [] } unless XApi.success?(resp)

      self_user_id = account.x_credential&.x_user_id.to_s
      replies = Array(resp.dig(:body, 'data')).filter_map do |ev|
        next unless ev['event_type'] == 'MessageCreate'
        next if self_user_id.present? && ev['sender_id'].to_s == self_user_id
        content = ev['text'].to_s.strip
        next if content.blank?
        { 'content' => content, 'observed_at' => ev['created_at'] }
      end

      { has_reply: replies.any?, replies: replies }
    end

    private

    # 解析对方 X user_id：优先用缓存 contact.x_user_id，否则按 @username 查并回写缓存。
    def resolve_participant_id(account, contact)
      return contact.x_user_id if contact.x_user_id.present?

      username = contact.url.to_s.strip.sub(/\A@/, '')
      return nil if username.blank?

      token = XAuthService.access_token_for(account)
      return nil if token.blank?

      resp = XApi.user_by_username(access_token: token, username: username)
      return nil unless XApi.success?(resp)

      uid = resp.dig(:body, 'data', 'id').to_s
      return nil if uid.blank?

      contact.update_column(:x_user_id, uid)
      uid
    rescue => e
      Rails.logger.error "[KolXOutreach] 解析 X user_id 失败: #{e.message}"
      nil
    end

    # 失败分类：401=token 失效（休眠账号重新授权）；403=对方拒绝/不接受私信（停用联系方式）
    def classify_failure(resp)
      code = resp[:code].to_i
      return 'account_risk' if code == 401
      return 'dm_refused' if code == 403
      'x_api_error'
    end

    # 提取 X API 错误信息（body['errors'] 数组 / title / detail 兜底）
    def extract_error(resp)
      body = resp[:body]
      return resp[:raw].to_s if body.blank?
      err = body['errors'].to_a.first
      return err['detail'] || err['title'] || err['message'] if err.is_a?(Hash)
      body['title'] || body['detail'] || resp[:raw].to_s
    end
  end
end
