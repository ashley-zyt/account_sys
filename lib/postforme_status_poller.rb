# postforme 状态轮询器。
#
# 每 1 分钟轮询两类「未确认终态」的记录：
#   1. 授权中（authorizing）的账号 —— 查 postforme 是否已完成授权，拿到 social_account_id
#   2. 处理中（processing）的发布 —— 查 postforme 发布结果，回写本系统任务 success/failed
#
# 都是拉模式（不依赖 postforme webhook），有未确认记录才实际调 postforme，否则空转。
module PostformeStatusPoller
  # 统一入口：轮询授权 + 轮询发布
  def self.run
    poll_authorizations
    poll_posts
  end

  # 轮询「授权中」的账号，确认授权是否完成
  def self.poll_authorizations
    PostformeAccount.where(auth_status: :authorizing).find_each do |pa|
      account = pa.account
      next unless account

      result = PostformeAuthService.check_authorization(account)
      Rails.logger.info "[PostformePoller] 账号 #{account.id} 授权成功 social_account_id=#{result[:social_account_id]}" if result
    rescue => e
      Rails.logger.error "[PostformePoller] 轮询授权异常: #{e.message}"
    end
  end

  # 轮询「处理中」的发布，回写任务终态
  def self.poll_posts
    PostformePost.where(status: :processing).find_each do |pp|
      next if pp.post_id.blank?

      task = pp.task
      next unless task

      resp = PostformeApi.post_result(post_id: pp.post_id)
      next unless resp[:code] == 200

      results = Array(resp[:body])
      result = results.find { |r| r['post_id'] == pp.post_id } || results.first
      next unless result

      if result['success'] == true
        mark_success(task, pp, result)
      elsif result['success'] == false
        mark_failed(task, pp, result)
      end
    rescue => e
      Rails.logger.error "[PostformePoller] 轮询发布异常: #{e.message}"
    end
  end

  # 发布成功：回写任务 success + 写日志 + 记录平台链接
  def self.mark_success(task, pp, result)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id
    platform_url = result.dig('platform_data', 'url').to_s

    pp.update!(status: :success, platform_url: platform_url)
    TaskReportHelper.update_task_status(task, 'success')
    TaskReportHelper.create_task_log(task, 'success', snapshot_account_id, snapshot_browser_id)
    Rails.logger.info "[PostformePoller] 任务 #{task.class.name}##{task.id} 发布成功（post_id=#{pp.post_id}）"
  end

  # 发布失败：回写任务失败（资源队列任务会重置回 pending）+ 写日志
  def self.mark_failed(task, pp, result)
    error_msg = result['error'].to_s.presence || 'postforme 发布失败'
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    pp.update!(status: :failed, error_msg: error_msg)
    TaskReportHelper.update_task_status(task, 'error', error_msg)
    TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, error_msg)
    Rails.logger.error "[PostformePoller] 任务 #{task.class.name}##{task.id} 发布失败（post_id=#{pp.post_id}）：#{error_msg}"
  end
end
