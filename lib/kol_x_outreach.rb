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
      if token.blank?
        log_send(contact, account, :failed, '账号未完成 X 认证或无有效 token')
        return { success: false, reason: 'account_risk', error: '账号未完成 X 认证或无有效 token' }
      end

      participant_id, resolve_error = resolve_participant_id(account, contact)
      if participant_id.blank?
        if %i[token_missing token_invalid].include?(resolve_error)
          # 账号 token 失效（不是 @username 无效）→ 休眠账号，别停用对方联系方式
          log_send(contact, account, :failed, '账号 token 失效，无法解析对方 user_id')
          return { success: false, reason: 'account_risk', error: '账号 token 失效，无法解析对方 user_id' }
        end
        log_send(contact, account, :failed, '无法解析对方 X user_id（@username 无效或用户不存在）')
        return { success: false, reason: 'target_invalid', error: '无法解析对方 X user_id（@username 无效或用户不存在）' }
      end

      resp = XApi.send_dm(access_token: token, participant_id: participant_id, text: content)
      if XApi.success?(resp)
        log_send(contact, account, :success, '发送成功')
        { success: true }
      else
        reason = classify_failure(resp, account: account)
        error = full_error(resp)
        blocked_reason = blocked_reason_for(resp)
        log_send(contact, account, :failed, error)
        { success: false, reason: reason, error: error, blocked_reason: blocked_reason }
      end
    end

    # 查回复（同步）：拉 1-1 会话最新 DM 事件，过滤出「对方发来的 MessageCreate」。
    # @return [Hash] { has_reply:, replies: [{ 'content'=>, 'observed_at'=> }, ...] }
    def fetch_replies(account:, contact:)
      token = XAuthService.access_token_for(account)
      return { has_reply: false, replies: [] } if token.blank?

      participant_id, = resolve_participant_id(account, contact)
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

    # 记录发私信日志（X API 同步通道：直接记最终状态，不经过 pending → 回调）
    def log_send(contact, account, status, message)
      KolActionLog.create!(
        action_type: KolActionLog::ACTION_SEND,
        kol_id: contact&.kol_id,
        kol_contact_id: contact&.id,
        account_id: account&.id,
        status: status == :success ? KolActionLog::STATUS_SUCCESS : KolActionLog::STATUS_FAILED,
        message: message
      )
    rescue => e
      Rails.logger.error "[KolXOutreach] 记录发私信日志失败: #{e.message}"
    end

    # 解析对方 X user_id：优先用缓存 contact.x_user_id，否则按 @username 查并回写缓存。
    # @return [Array] [user_id, error]：成功时 user_id 非空、error 为 nil；
    #   失败时 user_id 为 nil、error 为 :token_missing / :token_invalid（账号问题，应休眠账号）
    #   或 :user_not_found / :username_blank（@username 无效，应停用联系方式）
    def resolve_participant_id(account, contact)
      return [contact.x_user_id, nil] if contact.x_user_id.present?

      username = contact.url.to_s.strip.sub(/\A@/, '')
      return [nil, :username_blank] if username.blank?

      token = XAuthService.access_token_for(account)
      return [nil, :token_missing] if token.blank?

      resp = XApi.user_by_username(access_token: token, username: username)
      unless XApi.success?(resp)
        return [nil, resp[:code].to_i == 401 ? :token_invalid : :user_not_found]
      end

      uid = resp.dig(:body, 'data', 'id').to_s
      return [nil, :user_not_found] if uid.blank?

      contact.update_column(:x_user_id, uid)
      [uid, nil]
    rescue => e
      Rails.logger.error "[KolXOutreach] 解析 X user_id 失败: #{e.message}"
      [nil, :error]
    end

    # 失败分类：
    #   401 = token 失效 → account_risk（休眠账号重新授权）
    #   403 靠 detail 措辞（实测 v2 DM 返回 RFC 7807 无 code）：
    #     「do not have permission to DM / not allowed to send / this user」→ 对方拒绝 → dm_refused（停用联系方式）
    #     「This operation is not permitted.」→ 歧义（账号被限流 或 对方关闭私信），结合账号近期成功率判断
    #     其它 → account_risk
    def classify_failure(resp, account: nil)
      code = resp[:code].to_i
      return 'account_risk' if code == 401

      if code == 403
        xcode = extract_error_code(resp).to_i
        return 'dm_refused' if [63, 150].include?(xcode)
        return 'account_risk' if [326, 261, 220, 87].include?(xcode)

        detail = extract_error(resp).to_s.downcase
        # 明确「对方拒绝」的 detail
        return 'dm_refused' if detail.include?('do not have permission to dm') ||
                               detail.include?('not allowed to send') ||
                               detail.include?('direct message') ||
                               detail.include?('this user') ||
                               detail.include?('not following')
        # "This operation is not permitted." 歧义：结合账号近期成功率判断
        if detail.include?('not permitted')
          return 'dm_refused' if account && account_likely_healthy?(account)
          return 'account_risk'
        end
        return 'account_risk'
      end

      'x_api_error'
    end

    # 判断账号近期是否健康（成功率 >= 50% 且样本量足够）。
    # 用于区分「not permitted」是「账号被限流」还是「对方关闭私信」：
    #   健康账号的 not permitted = 对方关私信；失败率高的账号 = 账号被限流。
    def account_likely_healthy?(account)
      return true if account.nil?
      done = KolMessage.where(account_id: account.id, direction: :outgoing,
                              status: [:sent_success, :sent_failed])
                       .where(created_at: 3.days.ago..Time.current)
      total = done.count
      return true if total < 5  # 样本太少，默认健康（避免误判新账号）
      success = done.where(status: :sent_success).count
      success.to_f / total >= 0.5
    end

    # 提取 X 错误码 code（body['errors'][0]['code'] 或 body['code']），用于精确分类失败原因
    def extract_error_code(resp)
      body = resp[:body]
      return nil unless body.is_a?(Hash)
      err = body['errors'].to_a.first
      return err['code'] if err.is_a?(Hash) && err['code'].present?
      body['code']
    end

    # 把 X 错误码映射为「对方不可私信原因」（仅对方问题类 code 才有值）
    def blocked_reason_for(resp)
      case extract_error_code(resp).to_i
      when 63 then 'account_suspended'
      when 150 then 'followers_only'
      end
    end

    # 提取 X API 错误信息：优先取 detail（具体原因），其次 message/title，最后 raw 兜底
    def extract_error(resp)
      body = resp[:body]
      return resp[:raw].to_s if body.blank?
      err = body['errors'].to_a.first
      if err.is_a?(Hash)
        return err['detail'].presence || err['message'].presence || err['title'].presence || resp[:raw].to_s
      end
      body['detail'].presence || body['title'].presence || resp[:raw].to_s
    end

    # 完整错误信息：X 错误码 + detail（易读）+ X 返回的原始 JSON（raw，含 status/title/type），
    # 便于后续统一判断「发送账号问题」vs「对方拒收私信」。
    def full_error(resp)
      xcode = extract_error_code(resp)
      detail = extract_error(resp)
      raw = resp[:raw].to_s.strip
      parts = []
      parts << "code=#{xcode}" if xcode.present?
      parts << detail if detail.present?
      parts << raw if raw.present?
      parts.uniq.join(" || ")
    end
  end
end
