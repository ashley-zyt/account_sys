# 机器端异步任务回调结果处理器 —— 按 ref 分派，更新对应任务/记录状态。
#
# 供两处复用：
#   1. Api::V1::BrowserTasksController（机器端正常回调）
#   2. 超时兜底（下发后长时间无回调，主动查机器端真实状态后补处理）
class BrowserTaskResultHandler
  # 处理一次任务结果（按 ref 分派）
  # @param ref [String] account_sys 透传标识，如 "MoveTask:123" / "WarmupTask:456" / "Account:789" / "kol_message:12" / "kol_contact:34"
  # @param status [String] "success" / "failed"
  # @param message [String] 动作统计或错误信息
  # @param result [Object, nil] 任务详细结果
  # @return [Hash] { type:, message: }
  #
  # 注意：ref 指向的不是本系统任务（如外部系统直接调用机器端后回传）时，不会报错，
  # 而是静默忽略并返回 success —— 这类任务本就不该由 account_sys 处理。
  def self.process(ref:, status:, message:, result: nil)
    model_name, id = ref.to_s.split(':', 2)
    id = id.to_i

    case model_name
    when 'WarmupTask'      then handle_warmup(id, status, message)
    when 'Account'         then handle_fetch(ref, status, message)
    when 'kol_message'     then handle_kol_send(id, status, message)
    when 'kol_contact'     then handle_kol_reply(id, status, message, result)
    when 'PostformeAuth'   then handle_postforme_auth(id, status)
    else                        handle_publish(model_name, id, status, message)
    end
  end

  # 发布任务回调：按模型名 + id 定位任务，复用 TaskReportHelper 更新状态 + 写日志
  def self.handle_publish(model_name, id, status, message)
    task_model = model_name.safe_constantize
    unless task_model.is_a?(Class) && task_model < ApplicationRecord && WorkMode.for_model(task_model)
      # ref 指向的不是本系统的任务模型：说明该任务不是 account_sys 下发的（如外部系统直接调用机器端接口后回传），
      # 静默忽略即可，不当作错误返回。
      Rails.logger.info "[BrowserTaskResult] 非本系统任务（model=#{model_name.inspect} id=#{id}），忽略"
      return { type: 'success', message: '非本系统任务，忽略' }
    end

    task = task_model.find_by(id: id)
    return { type: 'success', message: '任务不存在，忽略' } unless task

    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    if status == 'success'
      Rails.logger.info "[BrowserTaskResult] 任务 #{model_name}##{id} 成功"
      TaskReportHelper.update_task_status(task, 'success')
      TaskReportHelper.create_task_log(task, 'success', snapshot_account_id, snapshot_browser_id)
    else
      Rails.logger.error "[BrowserTaskResult] 任务 #{model_name}##{id} 失败: #{message}"
      TaskReportHelper.update_task_status(task, 'error', message)
      TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, message)
    end

    { type: 'success', message: '已更新任务状态' }
  end

  # 养号回调：更新 WarmupTask + warmup_profile
  def self.handle_warmup(id, status, message)
    warmup_task = WarmupTask.find_by(id: id)
    return { type: 'success', message: '养号任务不存在，忽略' } unless warmup_task

    account = warmup_task.account

    if status == 'success'
      duration_minutes = extract_duration(message)
      warmup_task.update!(status: :success, executed_at: Time.current, error_msg: message, duration_minutes: duration_minutes)
      if account
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(last_warmup_at: Time.current, warmup_status: 'success')
      end
      Rails.logger.info "[BrowserTaskResult] 养号 WarmupTask##{id} 成功"
    else
      warmup_task.update!(status: :failed, error_msg: message, executed_at: Time.current)
      if account
        profile = account.warmup_profile || account.create_warmup_profile
        profile.update!(warmup_status: 'failed', last_warmup_at: Time.current)
      end
      Rails.logger.error "[BrowserTaskResult] 养号 WarmupTask##{id} 失败: #{message}"
    end

    { type: 'success', message: '已更新养号任务状态' }
  end

  # 采集回调：发文数据已由机器端通过 /api/v1/post_stats 回传落库，此处仅记录
  def self.handle_fetch(ref, status, message)
    Rails.logger.info "[BrowserTaskResult] 采集回调 ref=#{ref} status=#{status} message=#{message}"
    { type: 'success', message: '已记录采集完成' }
  end

  # 发私信回调：按 KolMessage id 定位，复用 KolOutreachApi.apply_send_result
  def self.handle_kol_send(id, status, message)
    kol_message = KolMessage.find_by(id: id)
    return { type: 'success', message: '私信记录不存在，忽略' } unless kol_message

    KolOutreachApi.apply_send_result(kol_message, success: (status == 'success'), error: message.presence)
    { type: 'success', message: '已更新私信发送状态' }
  end

  # 查回复回调：按 KolContact id 定位，从 result 提取 replies
  def self.handle_kol_reply(id, status, _message, result)
    contact = KolContact.find_by(id: id)
    return { type: 'success', message: '联系方式不存在，忽略' } unless contact

    return { type: 'success', message: '已记录（无回复）' } unless status == 'success'

    replies = result.is_a?(Hash) ? (result['replies'] || result[:replies]) : nil
    KolOutreachApi.apply_reply_result(contact, replies)
    { type: 'success', message: '已更新回复状态' }
  end

  # postforme 授权回调：机器端打开授权页后用户完成 OAuth，status=success 表示「已点击授权、页面已跳转」。
  # 立即查 postforme 反查 social_account_id 加速确认；若 postforme 数据尚未就绪（confirm 返回 nil），
  # 交给 PostformeStatusPoller 的 1 分钟轮询兜底，不报错。
  def self.handle_postforme_auth(id, status)
    return { type: 'success', message: '授权任务未成功，忽略' } unless status == 'success'

    account = Account.find_by(id: id)
    return { type: 'success', message: '账号不存在，忽略' } unless account

    result = PostformeAuthService.confirm_authorization(account)
    if result
      Rails.logger.info "[BrowserTaskResult] postforme 授权确认成功 account=#{id} social_account_id=#{result[:social_account_id]}"
    else
      Rails.logger.info "[BrowserTaskResult] postforme 授权回调已收到，但 postforme 数据未就绪，等待轮询器兜底 account=#{id}"
    end
    { type: 'success', message: '已处理授权回调' }
  end

  # 从养号返回信息里提取总时长（秒）→ 分钟，如 "总时长 720 秒, ..."
  def self.extract_duration(info)
    return nil unless info.to_s =~ /总时长\s*(\d+)\s*秒/
    ($1.to_i / 60.0).round(1)
  end
end
