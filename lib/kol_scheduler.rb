# KOL 自动化触达调度器
#
# 职责：
#   1. 扫描 Pending 状态的 KOL，按渠道优先级启动首次触达
#   2. 等待期到期的 Contacting KOL，切换至下一优先级渠道继续触达
#   3. 提供人工干预入口：立即联系（manual_contact）与人工打字发送（manual_send）
class KolScheduler
  WAIT_DAYS_MIN = 1
  WAIT_DAYS_MAX = 2
  SUSPEND_HOURS = 24
  RETRY_HOURS = 1

  class << self
    # 定时入口：自动化触达扫描
    def run
      setup_logger("kol_scheduler.log")
      Rails.logger.info "[KolScheduler] 开始自动化触达扫描"
      process_pending
      process_due_contacting
      Rails.logger.info "[KolScheduler] 自动化触达扫描完成"
    end

    # 扫描待触达队列
    def process_pending
      Kol.pending_queue.find_each do |kol|
        safely(kol) { run_outreach(kol, scenario: :first_contact) }
      end
    end

    # 处理等待期到期的触达中 KOL
    def process_due_contacting
      Kol.where(status: :contacting)
         .where("next_action_at IS NULL OR next_action_at <= ?", Time.current)
         .find_each do |kol|
        safely(kol) { advance(kol) }
      end
    end

    # 从指定起点起，按优先级遍历所有有效渠道尝试发送
    def run_outreach(kol, scenario:, skip_contact_ids: [])
      contacts = kol.kol_contacts
        .where(status: KolContact.statuses[:active])
        .where(messaging_enabled: true)
      contacts = contacts.where.not(id: skip_contact_ids) if skip_contact_ids.present?
      contacts = contacts.order(priority: :asc, id: :asc)

      contacts.each do |contact|
        outcome = send_on_contact(kol, contact, scenario: scenario)
        case outcome
        when :success then return true
        when :suspended then return false   # 无可用账号/临时失败，保留渠道下次重试
        when :exhausted then next           # 渠道失效，切换下一渠道
        end
      end

      kol.update!(status: :unresponsive)
      false
    end

    # 等待期到期：当前渠道标记为已放弃，切换下一渠道
    def advance(kol)
      current = kol.current_contact
      if current
        KolMessage.where(
          kol_id: kol.id,
          kol_contact_id: current.id,
          direction: KolMessage.directions[:outgoing],
          status: [KolMessage.statuses[:queued], KolMessage.statuses[:sent_success]]
        ).update_all(status: KolMessage.statuses[:ignored])
      end

      run_outreach(kol, scenario: :follow_up, skip_contact_ids: [current&.id].compact)
    end

    # ---- 人工干预 ----

    # 立即联系：最高优先级，绕过排队，可强制指定渠道/账号
    def manual_contact(kol, contact: nil, account: nil, content: nil)
      contact ||= kol.active_contacts.first
      return { ok: false, error: "该 KOL 没有可用联系渠道" } if contact.nil?

      account ||= KolAccountAllocator.allocate(contact.platform)
      return { ok: false, error: "该平台暂无可用的内部账号（可能已达每日上限或处于风控休眠）" } if account.nil?

      result = deliver_message(kol, contact, account, content: content.presence, source: :manual, scenario: :first_contact)

      case result
      when :success
        deadline = kol.latest_outgoing_message&.wait_until || next_wait_time
        kol.update!(
          status: :contacting,
          current_contact_id: contact.id,
          current_account_id: account.id,
          last_contacted_at: Time.current,
          next_action_at: deadline
        )
        { ok: true }
      when :target_invalid
        { ok: false, error: "目标渠道无效，请更换联系渠道" }
      when :account_risk
        { ok: false, error: "内部账号风控受限（已自动休眠），请更换账号后重试" }
      else
        { ok: false, error: "发送失败，请稍后重试" }
      end
    end

    # 人工打字发送（跟进/回复）
    def manual_send(kol, contact: nil, account: nil, content:)
      contact ||= kol.current_contact || kol.active_contacts.first
      return { ok: false, error: "缺少联系渠道" } if contact.nil?

      account ||= kol.current_account || KolAccountAllocator.allocate(contact.platform)
      return { ok: false, error: "缺少内部账号（可能已达上限或处于风控休眠）" } if account.nil?

      result = deliver_message(kol, contact, account, content: content, source: :manual, scenario: nil)

      case result
      when :success
        kol.update!(status: :negotiating) if kol.replied_unprocessed?
        { ok: true }
      when :target_invalid
        { ok: false, error: "目标渠道无效，请更换联系渠道" }
      when :account_risk
        { ok: false, error: "内部账号风控受限（已自动休眠），请更换账号后重试" }
      else
        { ok: false, error: "发送失败，请稍后重试" }
      end
    end

    private

    # 在单个渠道上发送（含内部账号风控重试）
    # 返回 :success / :suspended / :exhausted
    def send_on_contact(kol, contact, scenario:)
      attempted = []
      loop do
        account = KolAccountAllocator.allocate(contact.platform, exclude_ids: attempted)
        if account.nil?
          kol.update!(status: :pending, next_action_at: SUSPEND_HOURS.hours.from_now)
          return :suspended
        end
        attempted << account.id

        result = deliver_message(kol, contact, account, source: :auto, scenario: scenario)

        case result
        when :success then return :success
        when :account_risk then next
        when :target_invalid
          contact.update!(status: :invalid)
          return :exhausted
        else
          kol.update!(status: :pending, next_action_at: RETRY_HOURS.hours.from_now)
          return :suspended
        end
      end
    end

    # 发送单条消息并落库，返回 :success / :account_risk / :target_invalid / :other
    def deliver_message(kol, contact, account, content: nil, source: :auto, scenario: nil)
      content ||= render_content(kol, contact, account, scenario || :first_contact)
      template = scenario ? MessageTemplate.for(scenario: scenario, language: kol.language) : nil

      message = KolMessage.create!(
        kol: kol,
        kol_contact: contact,
        account: account,
        platform: contact.platform,
        direction: :outgoing,
        source: source,
        message_template: template,
        content: content,
        status: :queued,
        occurred_at: Time.current
      )

      result = KolOutreachApi.send_single_message(
        platform: contact.platform,
        account: account,
        contact: contact,
        content: content
      )

      if result[:success]
        deadline = next_wait_time
        message.update!(status: :sent_success, wait_until: deadline, occurred_at: Time.current)
        contact.update!(last_used_at: Time.current)

        # 自动化触达时推进 KOL 业务状态；人工发送时由上层决定状态流转
        unless source.to_s == "manual"
          kol.update!(
            status: :contacting,
            current_contact_id: contact.id,
            current_account_id: account.id,
            last_contacted_at: Time.current,
            next_action_at: deadline
          )
        end
        :success
      elsif result[:reason] == "account_risk"
        message.update!(status: :sent_failed, error_msg: "内部账号风控/受限")
        KolAccountAllocator.sleep_account(account)
        :account_risk
      elsif result[:reason] == "target_invalid"
        message.update!(status: :sent_failed, error_msg: "目标账号无效/隐私受限")
        :target_invalid
      else
        message.update!(status: :sent_failed, error_msg: result[:error] || result[:reason] || "发送失败")
        :other
      end
    end

    def render_content(kol, contact, account, scenario)
      template = MessageTemplate.for(scenario: scenario, language: kol.language)
      template ? template.render_with(kol: kol, account: account, contact: contact) : fallback_content(kol)
    end

    def fallback_content(kol)
      "Hi #{kol.name}, this is our team reaching out. Looking forward to connecting!"
    end

    def next_wait_time
      rand(WAIT_DAYS_MIN.days..WAIT_DAYS_MAX.days)
    end

    def safely(kol)
      yield
    rescue => e
      Rails.logger.error "[KolScheduler] KOL##{kol&.id} 处理异常: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
    end

    def setup_logger(file)
      logger = ActiveSupport::Logger.new(File.join(Rails.root, "log", file))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
