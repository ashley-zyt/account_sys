# KOL 自动化触达调度器
#
# 职责：
#   1. 扫描 Pending 状态的 KOL，按渠道优先级启动首次触达
#   2. 等待期到期的 Contacting KOL，切换至下一优先级渠道继续触达
#   3. 提供人工干预入口：立即联系（manual_contact）与人工打字发送（manual_send）
#   4. 模板匹配 + 变量校验：自动触达缺变量时跳过并标记；人工触达缺变量时阻断
class KolScheduler
  # 发出消息后等待对方回复的固定时长：48 小时
  REPLY_WAIT_HOURS = 48
  SUSPEND_HOURS = 24
  RETRY_HOURS = 1

  class << self
    def run
      setup_logger("kol_scheduler.log")
      Rails.logger.info "[KolScheduler] 开始自动化触达扫描"
      process_pending
      process_due_contacting
      Rails.logger.info "[KolScheduler] 自动化触达扫描完成"
    end

    def process_pending
      Kol.pending_queue.find_each do |kol|
        safely(kol) { run_outreach(kol, scenario: :first_contact) }
      end
    end

    def process_due_contacting
      Kol.where(status: :contacting)
         .where("next_action_at IS NULL OR next_action_at <= ?", Time.current)
         .find_each do |kol|
        safely(kol) { advance(kol) }
      end
    end

    # 从起点起按优先级遍历所有有效渠道尝试发送（仅处理已接通平台）
    def run_outreach(kol, scenario:, skip_contact_ids: [])
      contacts = kol.kol_contacts
        .where(status: KolContact.statuses[:active])
        .where(messaging_enabled: true)
      contacts = contacts.where.not(id: skip_contact_ids) if skip_contact_ids.present?
      contacts = contacts.order(priority: :asc, id: :asc).to_a
      contacts = contacts.select { |c| KolAccountAllocator.supported_platform?(c.platform) }

      contacts.each do |contact|
        outcome = send_on_contact(kol, contact, scenario: scenario)
        case outcome
        when :success then return true
        when :suspended then return false   # 无可用账号/缺变量/临时失败，停止本次
        when :exhausted then next           # 渠道失效，切换下一渠道
        end
      end

      kol.update!(status: :unresponsive)
      false
    end

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

      # 未提供自定义内容时，走模板 + 变量校验
      if content.blank?
        template = find_template(kol, contact, :first_contact)
        missing = template ? kol.missing_variables(template.required_variable_keys) : []
        return { ok: false, error: "缺少模板变量：#{missing.join('、')}" } if missing.any?
      end

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
      when :account_risk
        { ok: false, error: "内部账号异常（已自动休眠），请更换账号后重试" }
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
      when :account_risk
        { ok: false, error: "内部账号异常（已自动休眠），请更换账号后重试" }
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
        when :missing_variables then return :suspended
        when :account_risk then next
        else
          kol.update!(status: :pending, next_action_at: RETRY_HOURS.hours.from_now)
          return :suspended
        end
      end
    end

    # 发送单条消息并落库，返回 :success / :missing_variables / :account_risk / :target_invalid / :other
    def deliver_message(kol, contact, account, content: nil, source: :auto, scenario: nil)
      scenario ||= :first_contact

      # 模板匹配 + 变量校验（仅在未提供自定义内容时）
      template = nil
      if content.blank?
        template = find_template(kol, contact, scenario)
        missing = template ? kol.missing_variables(template.required_variable_keys) : []
        if missing.any?
          if source.to_s == "auto"
            kol.update!(variables_incomplete: true)
            Rails.logger.warn "[KolScheduler] KOL##{kol.id} 缺少变量 #{missing.join('、')}，标记待补全并跳过"
          end
          return :missing_variables
        end
        content = template ? template.render_for(kol) : fallback_content(kol)
      end

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
        message.update!(status: :sent_failed, error_msg: "内部账号异常")
        KolAccountAllocator.sleep_account(account)
        :account_risk
      else
        message.update!(status: :sent_failed, error_msg: result[:error] || result[:reason] || "发送失败")
        :other
      end
    end

    def find_template(kol, contact, scenario)
      MessageTemplate.match_for(
        scenario: scenario,
        platform: contact.platform,
        domain_id: kol.domain_id
      ).includes(:message_template_versions, :message_variables).order(:id).first
    end

    def fallback_content(kol)
      "Hi #{kol.name}, this is our team reaching out. Looking forward to connecting!"
    end

    def next_wait_time
      Time.current + REPLY_WAIT_HOURS.hours
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
