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
      next unless PostformeApi.success?(resp)

      results = PostformeApi.items(resp)
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
    error_msg = extract_error_message(result)
    snapshot_account_id = task.account_id
    snapshot_browser_id = task.browser_id

    pp.update!(status: :failed, error_msg: error_msg)
    TaskReportHelper.update_task_status(task, 'error', error_msg)

    # 写失败日志：之前 create_task_log 抛异常会被外层 poll_posts 的 rescue 吞掉，
    # 导致「任务已重置 pending、但 task_log 缺失」。这里单独捕获并记录完整异常，
    # 保证任务状态回写不受影响，异常也能拿到 backtrace 定位。
    begin
      TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, error_msg)
    rescue => e
      Rails.logger.error "[PostformePoller] 写失败 task_log 异常 #{task.class.name}##{task.id}: #{e.class} #{e.message}\n#{e.backtrace.first(6).join("\n")}"
    end

    Rails.logger.error "[PostformePoller] 任务 #{task.class.name}##{task.id} 发布失败（post_id=#{pp.post_id}）：#{error_msg}"
  end

  # 从 postforme 结果里提取友好错误信息。
  # error 是 object 类型（Hash），直接 to_s 会得到 Ruby hash 字符串、且可能带非法 UTF-8 字节；
  # 优先取 message / error / code 字段，拿不到再退回 to_s，最后 scrub 掉非法字节。
  def self.extract_error_message(result)
    err = result['error']
    msg = if err.is_a?(Hash)
            err['message'].presence || err['error'].presence || err['code'].presence || err.to_s
          else
            err.to_s
          end
    TaskReportHelper.safe_utf8(msg).presence || 'postforme 发布失败'
  end
end
