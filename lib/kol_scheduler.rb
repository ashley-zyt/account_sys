# KOL 自动化触达调度器
#
# 职责：
#   1. 扫描 Pending 状态的 KOL，按渠道优先级启动首次触达
#   2. 等待期到期的 Contacting KOL，切换至下一优先级渠道继续触达
#   3. 提供人工干预入口：立即联系（manual_contact）与人工打字发送（manual_send）
#   4. 模板匹配 + 变量校验：自动触达缺变量时跳过并标记；人工触达缺变量时阻断
class KolScheduler
  # 发出消息后等待对方回复的固定时长（工作日，自动跳过周六周日）
  REPLY_WAIT_DAYS = 2
  # 单个联系方式回复监测总时长（自然日，从最后一次发送成功起算）
  REPLY_MONITOR_DAYS = 30
  SUSPEND_HOURS = 24
  RETRY_HOURS = 1

  class << self
    def run
      setup_logger("kol_scheduler.log")
      Rails.logger.info "[KolScheduler] 开始自动化触达扫描"
      process_pending
      process_due_contacting
      process_contact_expiry
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

    # 向「尚未联系」的有效渠道发送（按优先级），返回是否有发送成功
    def run_outreach(kol, scenario:)
      contacts = kol.kol_contacts
        .where(status: KolContact.statuses[:active])
        .where(messaging_enabled: true)
        .order(priority: :asc, id: :asc)
        .to_a
        .select { |c| KolAccountAllocator.supported_platform?(c.platform) }

      return false if contacts.empty?

      contacts.each do |contact|
        outcome = send_on_contact(kol, contact, scenario: scenario)
        return true if outcome == :success
        return false if outcome == :suspended  # 无可用账号/缺变量/临时失败，停止本次
      end

      false
    end

    # 2 个工作日无回复后切换：尝试下一个「未联系」渠道；当前渠道保持 monitoring，交给 30 天过期处理
    def advance(kol)
      has_active = kol.kol_contacts.where(status: KolContact.statuses[:active]).exists?
      if has_active
        run_outreach(kol, scenario: :follow_up)
      else
        # 没有未联系渠道了，停止 advance；等待 30 天过期处理判定「无回应」
        kol.update!(next_action_at: nil)
      end
    end

    # 处理 30 天监测窗口到期的联系方式：标记为「无回应」，并重新评估 KOL 状态
    def process_contact_expiry
      expired = KolContact.where(status: KolContact.statuses[:contacting])
                          .where("monitor_until IS NOT NULL AND monitor_until <= ?", Time.current)
      return if expired.none?

      kol_ids = expired.distinct.pluck(:kol_id)
      expired.update_all(status: KolContact.statuses[:unresponsive])
      Rails.logger.info "[KolScheduler] #{kol_ids.size} 个 KOL 的联系方式监测到期"

      Kol.where(id: kol_ids).find_each do |kol|
        safely(kol) { reevaluate_kol_status(kol) }
      end
    end

    # 依据联系方式的独立状态，重算 KOL 的自动化状态（仅针对 pending / contacting）
    def reevaluate_kol_status(kol)
      return unless %w[pending contacting].include?(kol.status.to_s)

      if kol.kol_contacts.where(status: KolContact.statuses[:replied]).exists?
        kol.update!(status: :replied_unprocessed, next_action_at: nil)
      elsif kol.kol_contacts.where(status: KolContact.statuses[:contacting]).exists?
        kol.update!(status: :contacting)
      elsif kol.kol_contacts.where(status: KolContact.statuses[:active]).exists?
        kol.update!(status: :pending, next_action_at: nil)
      else
        kol.update!(status: :unresponsive, next_action_at: nil)
      end
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
        if kol.replied_unprocessed?
          kol.update!(status: :negotiating)
        elsif %w[pending reserved].include?(kol.status.to_s)
          # 人工已成功发消息：从「待联系/未开始」转为「联系中」，避免自动化再次触达
          deadline = kol.latest_outgoing_message&.wait_until || next_wait_time
          kol.update!(
            status: :contacting,
            current_contact_id: contact.id,
            current_account_id: account.id,
            last_contacted_at: Time.current,
            next_action_at: deadline
          )
        end
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

        # 联系方式状态流转：未回复的 → 监测中（30 天窗口）；已回复的保持 replied
        if contact.replied?
          contact.update!(last_used_at: Time.current)
        else
          contact.update!(status: :contacting, monitor_until: REPLY_MONITOR_DAYS.days.from_now, last_used_at: Time.current)
        end

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
      business_days_from_now(REPLY_WAIT_DAYS)
    end

    # 返回 N 个工作日后的时间点，自动跳过周六周日
    def business_days_from_now(days)
      t = Time.current
      count = 0
      while count < days
        t += 1.day
        count += 1 if t.wday.between?(1, 5) # 周一~周五
      end
      t
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
