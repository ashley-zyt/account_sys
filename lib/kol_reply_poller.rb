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
      # 异步受理：机器端后台执行，等 /api/v1/browser_tasks/result 回调后由 apply_reply_result 处理
      return if result[:async]
      return unless result[:has_reply]

      KolOutreachApi.apply_reply_result(contact, result[:replies])
    end

    private

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
