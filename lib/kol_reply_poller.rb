# KOL 状态轮询器
#
# 每 6 小时运行一次，检查 Contacting 状态下会话是否收到新回复；
# 收到回复后将 KOL 流转为 Replied_Unprocessed，暂停自动化并等待人工审阅。
class KolReplyPoller
  class << self
    def run
      setup_logger("kol_reply_poller.log")
      @stats = { kols: 0, due: 0, skipped: 0, replied: 0, advanced: 0, async: 0 }

      Rails.logger.info "[KolReplyPoller] ========== 开始回复轮询 =========="
      kol_ids = KolContact.where(status: KolContact.statuses[:contacting]).distinct.pluck(:kol_id)
      Rails.logger.info "[KolReplyPoller] 待检查 KOL 数：#{kol_ids.size}"

      Kol.where(id: kol_ids).find_each do |kol|
        @stats[:kols] += 1
        safely(kol) { poll(kol) }
      end

      Rails.logger.info "[KolReplyPoller] 轮询完成：检查 KOL #{@stats[:kols]} 个 | 到期联系方式 #{@stats[:due]} | 跳过 #{@stats[:skipped]} | 异步受理 #{@stats[:async]} | 发现回复 #{@stats[:replied]} 条 | 推进轮询 #{@stats[:advanced]}"
      Rails.logger.info "[KolReplyPoller] ========== 结束 =========="
    end

    def poll(kol)
      now = Time.current
      contacts = kol.kol_contacts.where(status: KolContact.statuses[:contacting]).to_a
      due = contacts.select { |c| c.next_poll_at.nil? || c.next_poll_at <= now }

      Rails.logger.info "[KolReplyPoller] KOL##{kol.id} #{kol.name}：联系中 #{contacts.size} 个，本次到期 #{due.size} 个"

      due.each do |contact|
        safely(kol) { poll_contact(kol, contact) }
      end
    end

    def poll_contact(kol, contact)
      unless contact.monitoring?
        @stats[:skipped] += 1
        Rails.logger.info "[KolReplyPoller]   contact##{contact.id}(#{contact.platform}) 监测已结束，跳过"
        return
      end

      account = contact.last_outgoing_account
      if account.nil?
        @stats[:skipped] += 1
        Rails.logger.info "[KolReplyPoller]   contact##{contact.id}(#{contact.platform}) 无成功发送记录，跳过"
        return
      end

      @stats[:due] += 1
      Rails.logger.info "[KolReplyPoller]   contact##{contact.id}(#{contact.platform}) 用账号##{account.id} 拉回复"

      result = if contact.outreach_channel == 'x_api'
        KolXOutreach.fetch_replies(account: account, contact: contact)
      else
        KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
      end

      if result[:async]
        @stats[:async] += 1
        Rails.logger.info "[KolReplyPoller]     异步受理，等机器端回调"
        return
      end

      if result[:has_reply]
        count = Array(result[:replies]).size
        @stats[:replied] += count
        KolOutreachApi.apply_reply_result(contact, result[:replies])
        Rails.logger.info "[KolReplyPoller]     发现 #{count} 条回复，已入库并转 replied"
      else
        nxt = next_poll_time(contact)
        contact.update!(next_poll_at: nxt)
        @stats[:advanced] += 1
        Rails.logger.info "[KolReplyPoller]     无回复，下次轮询推迟到 #{nxt.strftime('%Y-%m-%d %H:%M')}"
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
      logger.formatter = proc do |severity, time, _progname, msg|
        "#{time.strftime('%Y-%m-%d %H:%M:%S')} #{severity} -- #{msg}\n"
      end
      Rails.logger = logger
    end
  end
end
