class ExecuteWorker
  # 手动执行单个养号任务
  # @param warmup_task [WarmupTask] 养号任务对象
  def self.execute_warmup_task(warmup_task)
    return unless warmup_task&.account&.browser

    account = warmup_task.account
    machine = warmup_task.machine || 'other'

    # 生成操作列表（TikTok 不需要，但其他平台需要）
    operations = WarmupScheduler.generate_operations(account.platform)

    # 更新任务状态为执行中
    warmup_task.update!(status: :executing, operations: operations.to_json)

    begin
      endpoint = WarmupScheduler::NURTURE_ENDPOINTS[machine.to_sym]
      unless endpoint
        raise "机器模式 #{machine} 未配置养号接口"
      end

      request_data = WarmupScheduler.build_request_data(account, operations)
      response = WarmupScheduler.send_warmup_request(endpoint, request_data)

      if response['status'] == 'success'
        warmup_task.update!(status: :success, executed_at: Time.current, error_msg: response['info'])
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(last_warmup_at: Time.current, warmup_status: 'success')
      else
        error_msg = response['info'] || '养号失败'
        warmup_task.update!(status: :failed, error_msg: error_msg, executed_at: Time.current)
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(warmup_status: 'failed')
      end
    rescue => e
      warmup_task.update!(status: :failed, error_msg: e.message, executed_at: Time.current)
      profile = account.warmup_profile || account.create_warmup_profile
      profile.update!(warmup_status: 'failed')
    end
  end
end
