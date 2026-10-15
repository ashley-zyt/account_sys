# postpeer 状态轮询器。
#
# 轮询两类「未确认终态」的记录：
#   1. 授权中（authorizing）的账号 —— 查 postpeer 是否已完成授权，拿到 accountId
#   2. 处理中（processing）的发布 —— 查 postpeer 发布结果，回写本系统任务 success/failed
#
# 都是拉模式（不依赖 postpeer webhook），有未确认记录才实际调 postpeer，否则空转。
module PostpeerStatusPoller
  # 统一入口：轮询授权 + 轮询发布
  def self.run
    poll_authorizations
    poll_posts
  end

  # 轮询「授权中」的账号，确认授权是否完成
  def self.poll_authorizations
    PostpeerAccount.where(auth_status: :authorizing).find_each do |pa|
      account = pa.account
      next unless account

      result = PostpeerAuthService.check_authorization(account)
      Rails.logger.info "[PostpeerPoller] 账号 #{account.id} 授权成功 peer_account_id=#{result[:peer_account_id]}" if result
    rescue => e
      Rails.logger.error "[PostpeerPoller] 轮询授权异常: #{e.message}"
    end
  end

  # 轮询「处理中」的发布，回写任务终态
  def self.poll_posts
    PostpeerPost.where(status: :processing).find_each do |pp|
      next if pp.post_id.blank?

      task = pp.task
      next unless task

      resp = PostpeerApi.post_status(post_id: pp.post_id)
      next unless PostpeerApi.success?(resp)

      body = resp[:body]
      next unless body.is_a?(Hash)

      # postpeer 查询结果：post 数据嵌套在 body['post'] 里（顶层是 success + post）
      post_data = body['post'].is_a?(Hash) ? body['post'] : body

      status    = post_data['status'].to_s
      platforms = Array(post_data['platforms'])
      result    = platforms.first || {}

      if status == 'published' || result['status'] == 'published' || result['success'] == true
        mark_success(task, pp, result)
      elsif status == 'failed' || status == 'partial' || result['status'] == 'failed' || result['success'] == false
        mark_failed(task, pp, result)
      end
      # publishing / pending / scheduled 继续等待下轮
    rescue => e
      Rails.logger.error "[PostpeerPoller] 轮询发布异常: #{e.message}"
    end
  end

  # 发布成功：回写任务 success + 写日志 + 记录平台链接
  def self.mark_success(task, pp, result)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id
    platform_url = result['platformPostUrl'].to_s.gsub('`', '').strip

    pp.update!(status: :success, platform_url: platform_url)
    TaskReportHelper.update_task_status(task, 'success')
    TaskReportHelper.create_task_log(task, 'success', snapshot_account_id, snapshot_browser_id, nil, nil, 'postpeer')
    Rails.logger.info "[PostpeerPoller] 任务 #{task.class.name}##{task.id} 发布成功（post_id=#{pp.post_id}）"
  end

  # 发布失败：回写任务失败（资源队列任务会重置回 pending）+ 写日志
  def self.mark_failed(task, pp, result)
    error_msg = extract_error_message(result)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    pp.update!(status: :failed, error_msg: error_msg)
    TaskReportHelper.update_task_status(task, 'error', error_msg)

    begin
      TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, error_msg, nil, 'postpeer')
    rescue => e
      Rails.logger.error "[PostpeerPoller] 写失败 task_log 异常 #{task.class.name}##{task.id}: #{e.class} #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    end

    Rails.logger.error "[PostpeerPoller] 任务 #{task.class.name}##{task.id} 发布失败（post_id=#{pp.post_id}）：#{error_msg}"
  end

  # 从 postpeer 结果里提取友好错误信息。
  # error 可能是 string 或 object（Hash），优先取 message 字段，最后 safe_utf8。
  def self.extract_error_message(result)
    err = result['errorMessage'].presence || result['error']
    msg = if err.is_a?(Hash)
            err['message'].presence || err['error'].presence || err['code'].presence || err.to_s
          else
            err.to_s
          end
    TaskReportHelper.safe_utf8(msg).presence || 'postpeer 发布失败'
  end
end
