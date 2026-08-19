require "securerandom"
require "uri"
require "json"
require "httparty"

# KOL 触达远程 API 适配器
#
# 封装 send_single_message 与 check_reply 两个外部接口。当前后端真实接口尚未
# 确定，因此默认以 STUB 模式运行（send 恒成功、check_reply 恒无回复），保证整套
# 状态机可跑通；接入真实接口时，设置以下环境变量即可切换到真实 HTTP 调用：
#
#   KOL_OUTREACH_STUB_MODE=false
#   KOL_OUTREACH_API_URL=http://<host>:<port>/api/v1
#
class KolOutreachApi
  BASE_URL = ENV.fetch("KOL_OUTREACH_API_URL", "http://127.0.0.1:8080/api/v1")
  STUB_MODE = ENV.fetch("KOL_OUTREACH_STUB_MODE", "true") == "true"

  class << self
    # 发送单条私信
    # @return [Hash] { success:, reason:, message_id:, error:, raw: }
    #   reason 取值：account_risk / target_invalid / network / unknown
    def send_single_message(platform:, account:, contact:, content:)
      return stub_send if STUB_MODE

      response = HTTParty.post(
        "#{BASE_URL}/messages/send",
        headers: { "Content-Type" => "application/json" },
        body: {
          platform: platform,
          account_id: account&.id,
          account_name: account&.account_name,
          to: contact&.url.presence || contact&.nickname,
          content: content
        }.to_json,
        timeout: 30
      )
      parse_send_response(response)
    rescue => e
      Rails.logger.error "[KolOutreachApi] 发送异常: #{e.message}"
      { success: false, reason: "network", error: e.message, raw: nil }
    end

    # 检查指定会话是否有新回复
    # @return [Hash] { has_reply:, error:, raw: }
    def check_reply(platform:, account:, contact:)
      return { has_reply: false, raw: nil } if STUB_MODE

      response = HTTParty.get(
        "#{BASE_URL}/messages/check_reply",
        headers: { "Content-Type" => "application/json" },
        query: {
          platform: platform,
          account_id: account&.id,
          account_name: account&.account_name,
          to: contact&.url.presence || contact&.nickname
        },
        timeout: 30
      )
      parse_reply_response(response)
    rescue => e
      Rails.logger.error "[KolOutreachApi] 检查回复异常: #{e.message}"
      { has_reply: false, error: e.message, raw: nil }
    end

    private

    def stub_send
      { success: true, reason: nil, message_id: "stub-#{SecureRandom.hex(6)}", raw: nil }
    end

    def parse_send_response(response)
      return { success: false, reason: "network", raw: response&.body } unless response && (response.code == 200 || response.code == 201)

      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end
      code = (data["code"] || data["status"]).to_s

      case code
      when /success|ok|^0$|^200$/
        { success: true, reason: nil, message_id: data["message_id"] || data.dig("data", "message_id"), raw: data }
      when /risk|restricted|ban|limit/i
        { success: false, reason: "account_risk", raw: data }
      when /invalid|not_found|privacy|target/i
        { success: false, reason: "target_invalid", raw: data }
      else
        { success: false, reason: "unknown", raw: data }
      end
    end

    def parse_reply_response(response)
      return { has_reply: false, raw: response&.body } unless response && response.code == 200

      data = begin
        JSON.parse(response.body)
      rescue JSON::ParserError
        {}
      end
      has_reply = data["has_reply"] || data.dig("data", "has_reply") || data["reply"].present? || data.dig("data", "messages").present?
      { has_reply: !!has_reply, raw: data }
    end
  end
end
