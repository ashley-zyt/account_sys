# KOL 状态轮询器
#
# 每 6 小时运行一次，检查 Contacting 状态下会话是否收到新回复；
# 收到回复后将 KOL 流转为 Replied_Unprocessed，暂停自动化并等待人工审阅。
class KolReplyPoller
  class << self
    def run
      setup_logger("kol_reply_poller.log")
      Rails.logger.info "[KolReplyPoller] 开始回复轮询"
      # 轮询所有「监测中」联系方式所属的 KOL（多会话持续监测，而非只看当前联系方式）
      kol_ids = KolContact.where(status: KolContact.statuses[:contacting]).distinct.pluck(:kol_id)
      Kol.where(id: kol_ids).find_each do |kol|
        safely(kol) { poll(kol) }
      end
      Rails.logger.info "[KolReplyPoller] 回复轮询完成"
    end

    def poll(kol)
      kol.kol_contacts.where(status: KolContact.statuses[:contacting]).find_each do |contact|
        safely(kol) { poll_contact(kol, contact) }
      end
    end

    def poll_contact(kol, contact)
      account = contact.last_outgoing_account
      return if account.nil?

      result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
      return unless result[:has_reply]

      created = 0
      Array(result[:replies]).each do |reply|
        content = reply["content"].to_s.strip
        next if content.blank?
        next if already_stored?(kol, contact, content)

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

      # 该联系方式已回复，停止监测；KOL 转入待人工处理
      contact.update!(status: :replied, monitor_until: nil)
      kol.update!(status: :replied_unprocessed, next_action_at: nil)
      Rails.logger.info "[KolReplyPoller] KOL##{kol.id} 联系方式##{contact.id} 收到 #{created} 条回复，已转入待人工处理"
    end

    private

    # 按内容去重（同一 KOL + 同一联系方式），避免重复轮询重复入库
    def already_stored?(kol, contact, content)
      KolMessage.exists?(kol_id: kol.id, kol_contact_id: contact.id, direction: KolMessage.directions[:incoming], content: content)
    end

    def parse_time(str)
      Time.zone.parse(str)
    rescue
      nil
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
