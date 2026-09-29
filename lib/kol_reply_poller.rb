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
      now = Time.current
      kol.kol_contacts.where(status: KolContact.statuses[:contacting])
         .where("next_poll_at IS NULL OR next_poll_at <= ?", now)
         .find_each do |contact|
        safely(kol) { poll_contact(kol, contact) }
      end
    end

    def poll_contact(kol, contact)
      # 监测窗口已结束的不再轮询（交由 process_contact_expiry 标 unresponsive）
      return unless contact.monitoring?

      account = contact.last_outgoing_account
      return if account.nil?

      result = if contact.outreach_channel == 'x_api'
        KolXOutreach.fetch_replies(account: account, contact: contact)
      else
        KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
      end
      # 异步受理（仅机器端通道）：等 /api/v1/browser_tasks/result 回调后由 apply_reply_result 处理
      return if result[:async]

      if result[:has_reply]
        KolOutreachApi.apply_reply_result(contact, result[:replies])
      else
        # 无回复：按衰减频率推进下一次轮询时间
        contact.update!(next_poll_at: next_poll_time(contact))
      end
    end

    private

    # 距「最后发送成功」的整小时数（向下取整，避免 23.6h 被算成第二天）
    def elapsed_since_sent(contact)
      sent_at = contact.last_sent_at ||
                (contact.monitor_until && contact.monitor_until - KolScheduler.reply_monitor_days.days)
      return 0 if sent_at.nil?
      ((Time.current - sent_at) / 3600.0).to_i
    end

    # 根据距发送成功的小时数，返回下一次轮询应间隔的小时数：
    #   第一天（<24h）12h 一次；第 2~4 天（24~96h）每天一次；第 4 天之后（>=96h）每 3 天一次
    def poll_interval_hours(elapsed_hours)
      if elapsed_hours < 24
        12
      elsif elapsed_hours < 96
        24
      else
        72
      end
    end

    # 下一次轮询时间 = 现在 + 按当前 elapsed 算出的间隔
    def next_poll_time(contact)
      Time.current + poll_interval_hours(elapsed_since_sent(contact)).hours
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
