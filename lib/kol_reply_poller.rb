# KOL 状态轮询器
#
# 每 6 小时运行一次，检查 Contacting 状态下会话是否收到新回复；
# 收到回复后将 KOL 流转为 Replied_Unprocessed，暂停自动化并等待人工审阅。
class KolReplyPoller
  class << self
    def run
      setup_logger("kol_reply_poller.log")
      Rails.logger.info "[KolReplyPoller] 开始回复轮询"
      Kol.where(status: :contacting).find_each do |kol|
        safely(kol) { poll(kol) }
      end
      Rails.logger.info "[KolReplyPoller] 回复轮询完成"
    end

    def poll(kol)
      contact = kol.current_contact
      account = kol.current_account
      return unless contact

      result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
      return unless result[:has_reply]

      content = extract_reply_content(result)

      KolMessage.create!(
        kol: kol,
        kol_contact: contact,
        account: nil,
        platform: contact.platform,
        direction: :incoming,
        source: :auto,
        content: content,
        status: :replied,
        occurred_at: Time.current
      )

      # 暂停自动化，等待负责人人工审阅
      kol.update!(status: :replied_unprocessed, next_action_at: nil)
      Rails.logger.info "[KolReplyPoller] KOL##{kol.id} 收到回复，已转入待人工处理"
    end

    private

    def extract_reply_content(result)
      raw = result[:raw]
      if raw.is_a?(Hash)
        raw["content"] || raw.dig("data", "content") || raw.dig("data", "text") || "（收到回复）"
      else
        "（收到回复）"
      end
    end

    def safely(kol)
      yield
    rescue => e
      Rails.logger.error "[KolReplyPoller] KOL##{kol&.id} 轮询异常: #{e.message}"
    end

    def setup_logger(file)
      logger = ActiveSupport::Logger.new(File.join(Rails.root, "log", file))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
