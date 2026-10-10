# X（Twitter）API 发布轮询器。
#
# 拉模式完成 X 发布（不依赖 webhook）：每 1 分钟轮询「处理中」的 XPost，
#   1. 查媒体处理状态（视频转码中 → pending/in_progress；完成 → succeeded；失败 → failed）
#   2. 处理完成则发推（POST /2/tweets），回写本系统任务 success/failed
#
# 与 postforme 同构：XPublisher 负责「提交」（下载+上传+FINALIZE），本模块负责「完成」（轮询+发推）。
module XPostPoller
  # 统一入口：轮询所有「处理中」的 X 发布
  def self.run
    XPost.where(status: :processing).find_each do |xp|
      complete(xp)
    rescue => e
      Rails.logger.error "[XPostPoller] 处理 XPost##{xp.id} 异常: #{e.message}"
    end
  end

  # 处理单条「处理中」的 X 发布
  def self.complete(xp)
    return if xp.media_id.blank?

    task = xp.task
    return unless task

    account = task.account
    return unless account&.x_credential&.authorized?

    token = XAuthService.access_token_for(account)
    return if token.blank?

    # 1. 查媒体处理状态
    resp = XApi.media_upload_status(access_token: token, media_id: xp.media_id)
    return unless XApi.success?(resp)  # 查询失败（网络抖动等）→ 下轮再试

    body = resp[:body].is_a?(Hash) ? resp[:body] : {}
    data = body['data'].is_a?(Hash) ? body['data'] : {}
    info = data['processing_info']
    state = info.is_a?(Hash) ? info['state'].to_s : ''

    case state
    when 'succeeded', ''
      # 处理完成（或无 processing_info，视为已完成）→ 发推
      tweet_resp = XApi.create_tweet(access_token: token, text: tweet_text(task), media_ids: [xp.media_id])
      unless XApi.success?(tweet_resp)
        mark_failed(xp, task, "X 发推失败：#{tweet_resp[:raw].to_s.truncate(300)}")
        return
      end
      tweet_id = tweet_resp[:body].is_a?(Hash) ? tweet_resp[:body].dig('data', 'id').to_s : ''
      mark_success(xp, task, tweet_id)
    when 'failed'
      err = info.is_a?(Hash) ? info.dig('error', 'message').to_s : ''
      mark_failed(xp, task, "X 视频处理失败：#{err.presence || 'unknown'}")
    else
      # pending / in_progress → 下轮再查
    end
  end

  # 发布成功：回写任务 success + 写日志 + 记录 tweet_id
  def self.mark_success(xp, task, tweet_id)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    xp.update!(status: :success, tweet_id: tweet_id)
    TaskReportHelper.update_task_status(task, 'success')
    TaskReportHelper.create_task_log(task, 'success', snapshot_account_id, snapshot_browser_id)
    Rails.logger.info "[XPostPoller] 任务 #{task.class.name}##{task.id} 发布成功（tweet_id=#{tweet_id}）"
  end

  # 发布失败：回写任务失败（资源队列任务会按失败分类处理）+ 写日志
  def self.mark_failed(xp, task, error_msg)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    xp.update!(status: :failed, error_msg: error_msg)
    TaskReportHelper.update_task_status(task, 'error', error_msg)

    begin
      TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, error_msg)
    rescue => e
      Rails.logger.error "[XPostPoller] 写失败 task_log 异常 #{task.class.name}##{task.id}: #{e.class} #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    end

    Rails.logger.error "[XPostPoller] 任务 #{task.class.name}##{task.id} 发布失败（media_id=#{xp.media_id}）：#{error_msg}"
  end

  # 推文文案：title + 金融免责声明（与浏览器/第三方发布口径一致）
  def self.tweet_text(task)
    text = task.title.to_s
    text = FinancialDisclaimer.append(text) if FinancialDisclaimer.applies_to?(task.theme)
    text
  end
end
