require "securerandom"
require "uri"
require "json"
require "httparty"

# KOL 触达远程 API 适配器（真实接口）
#
# 发消息   POST /accounts/send_single_message
# 查回复   POST /accounts/check_reply
# host = 账号绑定浏览器的 machine_ip，端口 8080
#
# 异步模式：请求体带 async:true + ref，机器端立即返回 accepted+task_id，
# 后台执行完成后回调 /api/v1/browser_tasks/result；本文件同时承载「结果处理」公共方法，
# 供同步路径（kol_scheduler / kol_reply_poller）与回调路径（BrowserTasksController）复用。
class KolOutreachApi
  PORT = 8080
  PASSCODE = "1472"

  class << self
    # 发送单条私信
    # @param message_id [Integer, nil] 已创建的 KolMessage id，用于透传 ref 供回调定位
    # @return [Hash] 异步受理：{ async: true, task_id: }；同步：{ success:, reason:, message_id:, error:, raw: }
    #   reason: account_risk（内部账号异常，换账号） / network（网络异常，稍后重试）
    def send_single_message(platform:, account:, contact:, content:, message_id: nil)
      url = "#{base_url(account)}/accounts/send_single_message"
      body = {
        profile_name: account&.browser&.profile_name,
        platform: platform.to_s,
        target_url: contact&.outreach_target_url.to_s,
        message_content: content,
        account_id: account&.id,
        async: true,
        ref: message_id ? "kol_message:#{message_id}" : "kol_contact:#{contact&.id}"
      }
      body[:passcode] = PASSCODE if platform.to_s == "twitter"

      response = post_json(url, body)
      accepted = accepted_response(response)
      if accepted
        track_browser_task!(accepted["task_id"], body[:ref], 'send_message', body[:profile_name], account)
        KolActionLog.track!(
          action_type: KolActionLog::ACTION_SEND,
          kol_id: contact&.kol_id,
          kol_contact_id: contact&.id,
          account_id: account&.id,
          machine_task_id: accepted["task_id"],
          message: "发送私信"
        )
        return { async: true, task_id: accepted["task_id"] }
      end

      parse_send_response(response)
    rescue => e
      Rails.logger.error "[KolOutreachApi] 发送异常: #{e.message}"
      { success: false, reason: "network", error: e.message, raw: nil }
    end

    # 检查对方是否回复
    # @return [Hash] 异步受理：{ async: true, task_id: }；同步：{ has_reply:, replies:, error:, raw: }
    def check_reply(platform:, account:, contact:)
      url = "#{base_url(account)}/accounts/check_reply"
      body = {
        profile_name: account&.browser&.profile_name,
        platform: platform.to_s,
        target_url: contact&.outreach_target_url.to_s,
        account_id: account&.id,
        async: true,
        ref: "kol_contact:#{contact&.id}"
      }
      body[:passcode] = PASSCODE if platform.to_s == "twitter"

      response = post_json(url, body)
      accepted = accepted_response(response)
      if accepted
        track_browser_task!(accepted["task_id"], body[:ref], 'check_reply', body[:profile_name], account)
        KolActionLog.track!(
          action_type: KolActionLog::ACTION_CHECK,
          kol_id: contact&.kol_id,
          kol_contact_id: contact&.id,
          account_id: account&.id,
          machine_task_id: accepted["task_id"],
          message: "检查回复"
        )
        return { async: true, task_id: accepted["task_id"] }
      end

      parse_reply_response(response)
    rescue => e
      Rails.logger.error "[KolOutreachApi] 检查回复异常: #{e.message}"
      { has_reply: false, replies: [], error: e.message, raw: nil }
    end

    # ===== 结果处理（同步 + 回调共用）=====

    # 处理「发私信」最终结果：更新 KolMessage 状态 + contact/kol 状态流转。
    # @param message [KolMessage] 已创建的 outgoing 消息记录
    # @param success [Boolean] 是否发送成功
    # @param error   [String, nil] 失败原因
    # @param reason  [String, nil] 失败分类：account_risk / network；回调路径无法区分，传 nil（按 account_risk 休眠账号）
    def apply_send_result(message, success:, error: nil, reason: nil)
      return :failed unless message

      contact = message.kol_contact
      kol     = message.kol
      account = message.account

      if success
        deadline = next_wait_time
        message.update!(status: :sent_success, wait_until: deadline, occurred_at: Time.current)

        # 联系方式状态流转：未回复的 → 监测中（30 天窗口）；已回复的保持 replied
        if contact&.replied?
          contact.update!(last_used_at: Time.current)
        elsif contact
          contact.update!(status: :contacting, monitor_until: KolScheduler.reply_monitor_days.days.from_now, last_used_at: Time.current)
        end

        unless message.manual?
          kol.update!(
            status: :contacting,
            current_contact_id: contact&.id,
            current_account_id: account&.id,
            last_contacted_at: Time.current,
            next_action_at: deadline
          )
        end
        :success
      else
        message.update!(status: :sent_failed, error_msg: error.presence || "发送失败")
        # 仅 account_risk 才休眠账号；network 失败不休眠。回调路径无法区分，按 account_risk 处理（KOL 失败以账号异常为主）
        KolAccountAllocator.sleep_account(account) if account && reason != "network"
        :failed
      end
    end

    # 处理「查回复」最终结果：创建 incoming 消息 + 更新 contact/kol 状态。
    # @param contact [KolContact] 被检查的联系方式
    # @param replies [Array] 机器端返回的回复列表（[{ "content" =>, "observed_at" => }, ...]）
    def apply_reply_result(contact, replies)
      return unless contact

      kol     = contact.kol
      account = contact.last_outgoing_account
      created = 0

      Array(replies).each do |reply|
        reply = {} unless reply.is_a?(Hash)
        content = reply["content"].to_s.strip
        next if content.blank?
        next if KolMessage.exists?(kol_id: kol.id, kol_contact_id: contact.id,
                                  direction: KolMessage.directions[:incoming], content: content)

        KolMessage.create!(
          kol: kol,
          kol_contact: contact,
          account: account,
          platform: contact.platform,
          direction: :incoming,
          source: :auto,
          content: content,
          status: :replied,
          occurred_at: parse_time(reply["observed_at"]) || Time.current
        )
        created += 1
      end

      return if created.zero?

      contact.update!(status: :replied, monitor_until: nil)
      kol.update!(status: :replied_unprocessed, next_action_at: nil)
    end

    # N 个工作日之后（与 KolScheduler.next_wait_time 一致，供回调路径复用）
    def next_wait_time
      business_days_from_now(KolScheduler.reply_wait_days)
    end

    def business_days_from_now(days)
      t = Time.current
      count = 0
      while count < days
        t += 1.day
        count += 1 if t.wday.between?(1, 5) # 周一~周五
      end
      t
    end

    private

    # 登记异步任务到 BrowserTaskRecord，供后台「异步任务」页统一展示发私信/查回复进度
    def track_browser_task!(machine_task_id, ref, task_type, profile_name, account)
      return if machine_task_id.blank?
      BrowserTaskRecord.track!(
        machine_task_id: machine_task_id,
        ref: ref,
        task_type: task_type,
        profile_name: profile_name,
        machine_ip: account&.browser&.machine_ip
      )
    end

    # 判断响应是否为「异步受理」，是则返回解析后的 data（含 task_id），否则返回 nil
    def accepted_response(response)
      return nil unless response && response.code.to_i == 200
      data = JSON.parse(response.body)
      data["type"] == "accepted" ? data : nil
    rescue JSON::ParserError
      nil
    end

    def parse_time(str)
      Time.zone.parse(str)
    rescue
      nil
    end

    def base_url(account)
      ip = account&.browser&.machine_ip.to_s.strip
      raise "账号未绑定机器 IP" if ip.blank?
      "https://#{ip}"
    end

    def post_json(url, body)
      RemoteApiClient.post(url, body, read_timeout: 300)
    end

    def parse_send_response(response)
      unless response && (response.code.to_i == 200 || response.code.to_i == 201)
        return { success: false, reason: "network", error: "接口无响应或 HTTP #{response&.code}", raw: response&.body }
      end

      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end

      if data["type"] == "success" && data["status"] == "completed" && data.dig("result", "status") == "sent"
        { success: true, reason: nil, message_id: data["profile_id"], raw: data }
      else
        # 提取真实失败原因：优先 result.error_info，其次顶层 error_info，最后用 status 兜底
        error = data.dig("result", "error_info").presence || data["error_info"].presence || data["status"]
        # not_logged_in / failed / error 等均视为内部账号问题，换账号重试
        { success: false, reason: "account_risk", error: error, raw: data }
      end
    end

    def parse_reply_response(response)
      return { has_reply: false, replies: [], raw: response&.body } unless response && response.code.to_i == 200

      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end

      has_reply = data["has_reply"] || data["reply_status"] == "replied"
      { has_reply: !!has_reply, replies: data["replies"] || [], raw: data }
    end
  end
end
