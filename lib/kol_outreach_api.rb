require "securerandom"
require "uri"
require "json"
require "httparty"

# KOL 触达远程 API 适配器（真实接口）
#
# 发消息   POST /accounts/send_single_message
# 查回复   POST /accounts/check_reply
# host = 账号绑定浏览器的 machine_ip，端口 8080
class KolOutreachApi
  PORT = 8080
  PASSCODE = "1472"

  class << self
    # 发送单条私信
    # @return [Hash] { success:, reason:, message_id:, error:, raw: }
    #   reason: account_risk（内部账号异常，换账号） / network（网络异常，稍后重试）
    def send_single_message(platform:, account:, contact:, content:)
      url = "#{base_url(account)}/accounts/send_single_message"
      body = {
        profile_name: account&.browser&.profile_name,
        platform: platform.to_s,
        target_url: contact&.outreach_target_url.to_s,
        message_content: content,
        account_id: account&.id
      }
      body[:passcode] = PASSCODE if platform.to_s == "twitter"

      response = post_json(url, body)
      parse_send_response(response)
    rescue => e
      Rails.logger.error "[KolOutreachApi] 发送异常: #{e.message}"
      { success: false, reason: "network", error: e.message, raw: nil }
    end

    # 检查对方是否回复
    # @return [Hash] { has_reply:, replies:, error:, raw: }
    def check_reply(platform:, account:, contact:)
      url = "#{base_url(account)}/accounts/check_reply"
      body = {
        profile_name: account&.browser&.profile_name,
        platform: platform.to_s,
        target_url: contact&.outreach_target_url.to_s,
        account_id: account&.id
      }
      body[:passcode] = PASSCODE if platform.to_s == "twitter"

      response = post_json(url, body)
      parse_reply_response(response)
    rescue => e
      Rails.logger.error "[KolOutreachApi] 检查回复异常: #{e.message}"
      { has_reply: false, replies: [], error: e.message, raw: nil }
    end

    private

    def base_url(account)
      ip = account&.browser&.machine_ip.to_s.strip
      raise "账号未绑定机器 IP" if ip.blank?
      "http://#{ip}"
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
