class ExecuteWorker
  # 手动执行单个养号任务
  # 端点由该任务浏览器的 machine_ip 决定（与定时调度保持一致）
  # @param warmup_task [WarmupTask] 养号任务对象
  def self.execute_warmup_task(warmup_task)
    return unless warmup_task&.account&.browser

    account = warmup_task.account
    browser = account.browser

    # 端点取自浏览器所属运营机器；若未设置则报错并标记失败
    machine_ip = browser.machine_ip.presence || warmup_task.machine.presence
    unless machine_ip.present?
      error_msg = "浏览器 #{browser.profile_name} 未设置运营机器 IP，无法执行养号"
      Rails.logger.error "[ExecuteWorker] #{error_msg}"
      warmup_task.update!(status: :failed, error_msg: error_msg, executed_at: Time.current)
      profile = account.warmup_profile || account.create_warmup_profile
      profile.update!(warmup_status: 'failed')
      return
    end

    endpoint = "http://#{machine_ip}/accounts/nurture"

    # 更新任务状态为执行中，并记录执行机器
    warmup_task.update!(status: :executing, machine: machine_ip)

    begin
      request_data = {
        profile_name: browser.profile_name,
        platform: account.platform
      }

      response = WarmupScheduler.send_request(endpoint, request_data)

      if response['status'] == 'success'
        warmup_task.update!(status: :success, executed_at: Time.current, error_msg: response['info'])
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(last_warmup_at: Time.current, warmup_status: 'success')
      else
        error_msg = response['info'] || '养号失败'
        Rails.logger.error "[ExecuteWorker] 养号失败: 机器 #{machine_ip} / 账号 #{account.account_name} / 原因: #{error_msg}"
        warmup_task.update!(status: :failed, error_msg: error_msg, executed_at: Time.current)
        profile = account.warmup_profile || account.create_warmup_profile
        # 即使失败也更新 last_warmup_at，避免无限重试
        profile.update!(warmup_status: 'failed', last_warmup_at: Time.current)
      end
    rescue => e
      Rails.logger.error "[ExecuteWorker] 养号异常: 机器 #{machine_ip} / 账号 #{account.account_name} / 原因: #{e.message}"
      warmup_task.update!(status: :failed, error_msg: e.message, executed_at: Time.current)
      profile = account.warmup_profile || account.create_warmup_profile
      profile.update!(warmup_status: 'failed', last_warmup_at: Time.current)
    end
  end
end
