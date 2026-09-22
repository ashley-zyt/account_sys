# 运营机器「Undetectable 未启动 → 任务被暂停」的自动监测、自动恢复与告警
#
# 背景（机器端行为，见 ag_center `cmd/server/scheduler.go` 的 finalizeAsyncTask）：
#   任务因「Undetectable 未启动」失败时，机器端把它标成 paused 并**刻意不回调 account_sys**
#   （避免把「软件没起」误记成任务失败、污染成功率）。熔断冷却只有 30 秒，Undetectable 恢复后
#   新任务入口会自动解除熔断；但**已经 paused 的任务不会自己重跑**——必须有人调
#   `POST /tasks/resume` 触发本机重放，否则会一直挂着。
#
# 本监控的闭环（每 5 分钟一轮，见 config/schedule.rb）：
#   1. 查各机器 `GET /tasks?status=paused`；没有暂停任务 → 结束本轮周期（下次暂停重新计时）
#   2. 有暂停任务 → 调 `POST /tasks/resume`
#        · 200：熔断已清、Undetectable 可用；机器端会把**带 payload 的发布类**任务重新入队
#        · 503：仍未恢复 → 只累计时长。**此时不做任何重发**，因为重发同样会被同一熔断挡回来，
#               只会刷出一堆无谓的失败任务
#   3. resume 成功后，把**非发布类**任务（养号/采集/发私信/查回复）交给 account_sys 重新下发
#      —— 机器端只重放 `Payload != "" && type 以 _publish 结尾` 的任务（见 registerTask 调用点），
#         这四类的 payload 是空串，机器端救不了，只能由下发方重发
#   4. 暂停持续超过 THRESHOLD（默认 20 分钟）且本轮未提醒过 → 用 agic_zyt 发**一次**钉钉
#
# 幂等与安全：
#   - 非发布类重发后会清掉机器端对应类型的 paused 僵尸记录（否则每轮都会当成"新暂停"重复重发）
#   - 提醒按「暂停周期」只发一次（MachinePauseState#notified_at），恢复正常才重置
#   - 重发前会校验本地任务/账号是否仍然可用，不可用的只收尾登记记录、不重发
module MachinePauseMonitor
  # 暂停多久仍未恢复就发钉钉告警
  THRESHOLD = 20.minutes
  # 钉钉机器人（config/dingtalk.yml）
  ROBOT = :agic_zyt
  # resume 内部要探测 Undetectable（必要时拉起，最多约 20 秒），超时给足
  RESUME_TIMEOUT = 70
  # 单机单轮最多看多少条暂停任务（机器端 /tasks 上限 500）
  LIST_LIMIT = MachineTaskMonitor::LIST_MAX_LIMIT

  # 机器端无法本机重放、必须由 account_sys 重新下发的任务类型
  # （它们下发时 payload 传的是空串：fetch / nurture / send_message / check_reply）
  NON_PUBLISH_TYPES = MachineTaskMonitor::NON_PUBLISH_TYPES

  class << self
    # 入口：扫一遍所有机器（由定时任务每 5 分钟调用）
    def run
      ips = MachineTaskMonitor.machine_ips
      if ips.empty?
        Rails.logger.info "[MachinePauseMonitor] 没有配置运营机器，跳过"
        return
      end

      Rails.logger.info "[MachinePauseMonitor] 开始检查 #{ips.size} 台机器的暂停任务：#{ips.join(', ')}"

      # 第一步并行取各机器快照（线程内只发 HTTP、不碰 ActiveRecord，参照 MachineTaskMonitor.fetch_all）
      snapshots = ips.map { |ip| Thread.new { [ip, fetch_paused(ip)] } }.map(&:value).to_h

      # 第二步在主线程逐台处理（含数据库读写与 resume 调用）
      snapshots.each do |ip, paused|
        next if paused.nil? # 查询失败（机器不可达/超时），保持原状态，下一轮再试

        begin
          process(ip, paused)
        rescue => e
          Rails.logger.error "[MachinePauseMonitor] 处理 #{ip} 异常: #{e.class} #{e.message}"
        end
      end

      Rails.logger.info "[MachinePauseMonitor] 本轮检查完成"
    end

    # 查某台机器当前处于 paused 的任务明细
    # @return [Array<Hash>, nil] 成功返回统一结构数组（可能为空），失败返回 nil
    def fetch_paused(machine_ip)
      # own_only: false —— resume 是整机操作、无法按 ref 过滤，所以只要机器上有因
      # Undetectable 暂停的任务就处理；人工/外部的任务也会被"顺手救活"（这正是期望行为）
      result = MachineTaskMonitor.fetch_tasks(machine_ip, statuses: 'paused', limit: LIST_LIMIT, own_only: false)
      unless result.ok
        Rails.logger.warn "[MachinePauseMonitor] 查询 #{machine_ip} 暂停任务失败：#{result.error}"
        return nil
      end

      tasks = MachineTaskMonitor.normalize_tasks(result.data)
      tasks.select { |t| t[:status].to_s == 'paused' }
    end

    # 处理单台机器
    def process(machine_ip, paused)
      state = MachinePauseState.find_or_initialize_by(machine_ip: machine_ip)

      # 已无暂停任务：结束本轮周期（保留 resumed_at 便于排查「上次什么时候自己好的」）
      if paused.empty?
        if state.persisted? && state.paused_since.present?
          Rails.logger.info "[MachinePauseMonitor] #{machine_ip} 已无暂停任务，结束本轮暂停周期"
          state.finish_cycle!(message: '已无暂停任务')
        end
        return
      end

      # 累计本轮暂停周期：起始时刻优先沿用已有值，其次取机器端最早进入 paused 的时间
      # （机器端 finishTask 会把 updated_at 写成进入 paused 的时刻）
      state.paused_since ||= earliest_paused_at(paused) || Time.current
      state.paused_count = paused.size
      state.save! if state.new_record? || state.changed?

      # 尝试自动恢复：机器端会清熔断 → 探测（必要时拉起）Undetectable → 重放带 payload 的发布任务
      if try_resume(machine_ip)
        detail = redispatch_non_publish(machine_ip, paused)
        state.finish_cycle!(resumed: true, message: "已自动恢复：#{detail}")
        Rails.logger.info "[MachinePauseMonitor] #{machine_ip} Undetectable 已恢复，任务已自动继续（#{detail}）"
        return
      end

      # 仍未恢复：只累计时长，不做任何重发（重发也会被熔断挡回，还会刷出失败任务）
      elapsed = state.paused_seconds
      return if elapsed < THRESHOLD.to_i
      return if state.notified?

      # 发送成功才记 notified_at —— 本轮只提醒一次；若发送失败（钉钉不可达/被限流）
      # 则不记录，下一轮再试，避免"本该告警却静默丢掉"
      if notify(machine_ip, paused, state)
        state.update!(notified_at: Time.current,
                      last_message: "已发钉钉提醒（暂停 #{paused.size} 个任务，已等待 #{elapsed / 60} 分钟）")
      end
    end

    # 调机器端 POST /tasks/resume
    # @return [Boolean] true = 已恢复（Undetectable 可用，发布类任务已重新入队）
    def try_resume(machine_ip)
      url = "https://#{machine_ip}/tasks/resume"
      resp = RemoteApiClient.post(url, {}, read_timeout: RESUME_TIMEOUT)

      if resp.code.to_i == 200
        body = JSON.parse(resp.body.to_s) rescue {}
        Rails.logger.info "[MachinePauseMonitor] #{machine_ip} resume 成功，机器端重放 #{body['count'].to_i} 个发布任务"
        true
      else
        info = (JSON.parse(resp.body.to_s)['error_info'] rescue nil)
        Rails.logger.info "[MachinePauseMonitor] #{machine_ip} 暂未恢复（HTTP #{resp.code}）：#{info || resp.body.to_s[0, 200]}"
        false
      end
    rescue => e
      Rails.logger.error "[MachinePauseMonitor] #{machine_ip} resume 异常: #{e.class} #{e.message}"
      false
    end

    # resume 成功后，把机器端救不了的非发布类任务交给 account_sys 重新下发
    #
    # 分派规则（按 ref 前缀，与下发代码保持一致）：
    #   WarmupTask:<id>            → 重新下发养号
    #   Account:<id>               → 重新下发采集
    #   kol_message:<id> / kol_contact:<id> → 不主动重发（避免重复发私信），
    #                                 只把该 KOL 的 next_action_at 提前，交给 KolScheduler /
    #                                 KolReplyPoller 下一轮自然重跑
    # @return [String] 处理结果摘要（写入 MachinePauseState#last_message）
    def redispatch_non_publish(machine_ip, paused)
      nurture_refs = []
      fetch_refs   = []
      kol_refs     = []
      handled      = []   # 需要收尾本地登记记录的机器端 task_id
      affected_types = []

      paused.each do |t|
        type = t[:type].to_s
        next unless NON_PUBLISH_TYPES.include?(type) # 发布类交给机器端 resume

        affected_types << type
        handled << t
        ref = t[:ref].to_s

        case ref.split(':', 2).first
        when 'WarmupTask' then nurture_refs << ref if warmup_redispatchable?(ref)
        when 'Account'    then fetch_refs   << ref if fetch_redispatchable?(ref)
        when 'kol_message', 'kol_contact' then kol_refs << ref
        end
      end

      # 先清掉机器端这些类型的 paused 僵尸记录：它们的执行权已经交回 account_sys，
      # 留在机器端只会让下一轮又当成"新暂停"重复触发。
      # 用 type + status 双条件，范围最小化（只动这四类的 paused，不碰 success/failed/queued/running）
      clear_machine_paused_records(machine_ip, affected_types.uniq)

      nurture_count = TaskScheduler.retry_nurture_by_refs(nurture_refs)
      fetch_count   = TaskScheduler.retry_fetch_by_refs(fetch_refs)
      kol_count     = nudge_kol_retry(kol_refs)

      # 旧的养号任务不会再执行了：标失败并写明原因（它不在 WorkMode.resource_modes 里，
      # 不会被 check_timeout_tasks 的第 2 段兜底扫到，必须在这里收尾）
      nurture_refs.each { |ref| close_warmup_task(ref) }

      finish_local_records(handled, '因 Undetectable 未启动暂停，已由自动恢复重新下发')

      summary = []
      summary << "养号重发 #{nurture_count} 条" if nurture_refs.any?
      summary << "采集重发 #{fetch_count} 条"   if fetch_refs.any?
      summary << "私信/查回复交由 KOL 调度器重试 #{kol_count} 条" if kol_refs.any?
      summary << "发布类由机器端本机重放"
      summary.join('，')
    rescue => e
      Rails.logger.error "[MachinePauseMonitor] #{machine_ip} 非发布类重发异常: #{e.class} #{e.message}"
      "非发布类重发异常：#{e.message}"
    end

    # 清掉机器端指定类型的 paused 记录（POST /tasks/clear?type=...&status=paused）
    def clear_machine_paused_records(machine_ip, types)
      types = Array(types).reject(&:blank?).uniq
      return if types.empty?

      query = { type: types.join(','), status: 'paused' }.to_query
      url   = "https://#{machine_ip}/tasks/clear?#{query}"
      resp  = RemoteApiClient.post(url, {}, read_timeout: 30)
      count = (JSON.parse(resp.body.to_s)['count'] rescue nil)
      Rails.logger.info "[MachinePauseMonitor] #{machine_ip} 清理 #{types.join('/')} 的 paused 记录：#{resp.code} count=#{count}"
    rescue => e
      Rails.logger.error "[MachinePauseMonitor] #{machine_ip} 清理 paused 记录异常: #{e.class} #{e.message}"
    end

    # 收尾本地登记记录：机器端那条任务已经作废（执行权已交回 account_sys 重新下发），
    # 不置终态的话会永远挂在"执行中"，超时兜底也识别不出来（它查机器端只会看到 paused→跳过）
    def finish_local_records(tasks, message)
      tasks.each do |t|
        machine_task_id = t[:id].to_s
        next if machine_task_id.blank?

        BrowserTaskRecord.where(machine_task_id: machine_task_id)
                         .update_all(status: BrowserTaskRecord::STATUS_UNKNOWN,
                                     message: message, updated_at: Time.current)
        KolActionLog.where(machine_task_id: machine_task_id)
                    .update_all(status: KolActionLog::STATUS_FAILED,
                                message: message, updated_at: Time.current)
      end
    end

    # 把 KOL 的 next_action_at 提前到当前，让 KolScheduler（发私信）/ KolReplyPoller（查回复）
    # 下一轮自然重跑；不直接重发是为了避免重复发私信
    def nudge_kol_retry(refs)
      count = 0
      refs.each do |ref|
        model_name, id = ref.split(':', 2)
        kol = case model_name
              when 'kol_message' then KolMessage.find_by(id: id.to_i)&.kol
              when 'kol_contact' then KolContact.find_by(id: id.to_i)&.kol
              end
        next if kol.nil?

        kol.update!(next_action_at: Time.current) if kol.next_action_at.nil? || kol.next_action_at > Time.current
        count += 1
      rescue => e
        Rails.logger.error "[MachinePauseMonitor] 提前 KOL 重试时间失败 #{ref}: #{e.message}"
      end
      count
    end

    # 养号是否值得重发：本地任务仍在执行中、且账号/浏览器/机器信息齐全
    def warmup_redispatchable?(ref)
      _, id = ref.split(':', 2)
      task = WarmupTask.find_by(id: id.to_i)
      return false if task.nil?

      account = task.account
      return false if account.nil? || account.browser&.machine_ip.blank?

      # 已被兜底标失败/成功的旧任务不再重发（避免重复养号）
      task.status == 'executing'
    end

    # 采集是否值得重发：账号仍存在且绑定了机器
    def fetch_redispatchable?(ref)
      _, id = ref.split(':', 2)
      account = Account.find_by(id: id.to_i)
      account.present? && account.browser&.machine_ip.present?
    end

    # 旧养号任务已由本次重新下发取代 → 标失败并写明原因
    def close_warmup_task(ref)
      _, id = ref.split(':', 2)
      WarmupTask.where(id: id.to_i, status: WarmupTask.statuses[:executing])
                .update_all(status: WarmupTask.statuses[:failed],
                            error_msg: '因 Undetectable 未启动暂停，已自动重新下发',
                            updated_at: Time.current)
    end

    # 发钉钉告警（本轮只发一次，由 MachinePauseState#notified_at 保证）
    # @return [Boolean] 是否发送成功
    def notify(machine_ip, paused, state)
      minutes = state.paused_seconds / 60
      own     = paused.count { |t| t[:source] == 'account_sys' }
      manual  = paused.size - own

      type_desc = paused.group_by { |t| t[:type_label].to_s }
                        .map { |label, list| "#{label} #{list.size} 条" }.join('、')
      profiles = paused.map { |t| t[:profile_name] }.compact.reject(&:empty?).uniq
      profile_desc = profiles.first(5).join('、')
      profile_desc += " 等 #{profiles.size} 个" if profiles.size > 5

      content = [
        "【任务暂停告警】机器 #{machine_ip}",
        "Undetectable 已停止约 #{minutes} 分钟，仍有 #{paused.size} 个任务被暂停，自动恢复未成功。",
        "任务构成：#{type_desc}",
        ('涉及环境：' + profile_desc if profile_desc.present?),
        "来源：本系统下发 #{own} 条#{manual.positive? ? "、人工/外部 #{manual} 条" : ''}",
        '请远程启动 Undetectable 主程序（或检查机器是否离线）；启动后系统会在 5 分钟内自动恢复，'
      ].compact.join("\n")

      if Dingtalk.send_text(ROBOT, content)
        Rails.logger.info "[MachinePauseMonitor] #{machine_ip} 已发钉钉告警（#{ROBOT}）"
        true
      else
        Rails.logger.error "[MachinePauseMonitor] #{machine_ip} 钉钉告警发送失败（检查 config/dingtalk.yml 的 #{ROBOT}），下一轮重试"
        false
      end
    end

    # 暂停任务里最早进入 paused 的时刻（机器端 updated_at 在进入 paused 时被写入）
    def earliest_paused_at(paused)
      times = paused.map { |t| parse_time(t[:updated_at] || t[:created_at]) }.compact
      times.min
    end

    def parse_time(value)
      return nil if value.blank?
      return value if value.is_a?(Time) || value.is_a?(DateTime)

      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
