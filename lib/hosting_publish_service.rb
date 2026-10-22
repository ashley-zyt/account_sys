# 客户托管发布服务：从资源队列取成品生成托管发布任务，并按渠道执行发布。
#
# 取成品规则：按托管账号指定的「资源队列 + 主题 + 平台」取一条未消费、非终态的成品，
# 生成 hosting_publish_tasks，并通过 resource_type + resource_id 唯一索引避免重复发。
#
# 发布执行按 hosting_account.publish_channel 分支：
#   postpeer  → PostpeerApi.create_post（同步）
#   postforme → PostformeApi.create_post + 轮询结果
#   x_api     → X 上传视频 + 转码轮询 + 发推
module HostingPublishService
  # 取一条成品并生成托管发布任务
  # @return [Hash] { success: true, task: } 或 { success: false, message: }
  def self.fetch_and_create_task(hosting_account)
    wm = WorkMode.find(hosting_account.resource_queue)
    return { success: false, message: '未配置资源队列' } if wm.nil? || !wm.resource?
    return { success: false, message: '未配置主题' } if hosting_account.theme.blank?

    model = wm.task_model_class

    # 已被托管消费的成品 ID（避免重复发）
    consumed_ids = HostingPublishTask.where(resource_type: model.name).pluck(:resource_id)

    scope = model.where(theme: hosting_account.theme, platform: hosting_account.platform)
    scope = scope.where.not(id: consumed_ids) if consumed_ids.any?
    scope = scope.where.not(status: [:success, :failed])
    resource = scope.order(created_at: :asc).first

    return { success: false, message: '该主题/平台下暂无可用成品' } if resource.nil?

    task = HostingPublishTask.create!(
      resource_type: model.name,
      resource_id: resource.id,
      platform: hosting_account.platform,
      theme: hosting_account.theme,
      hosting_account_id: hosting_account.id,
      client_id: hosting_account.client_id,
      publish_channel: hosting_account.publish_channel,
      status: :pending
    )
    { success: true, task: task }
  rescue ActiveRecord::RecordNotUnique
    { success: false, message: '该成品已被消费，请重试' }
  end

  # 执行发布：按托管账号配置的发布渠道分支
  # @return [Hash] { success:, message: }
  def self.publish(task)
    case task.publish_channel.to_s
    when 'postpeer'  then publish_postpeer(task)
    when 'postforme' then publish_postforme(task)
    when 'x_api'     then publish_x_api(task)
    else
      task.update!(status: :failed, executed_at: Time.current, error_msg: "未知发布渠道 #{task.publish_channel}")
      { success: false, message: "未知发布渠道 #{task.publish_channel}" }
    end
  end

  # postpeer：同步提交并回写
  def self.publish_postpeer(task)
    pa = task.hosting_account.postpeer_account
    return { success: false, message: '托管账号未完成 postpeer 授权' } unless pa&.authorized?

    resource = task.resource
    return { success: false, message: '成品不存在' } if resource.nil?

    video_url = video_url_for(task, resource)
    content = extract_content(resource)

    resp = PostpeerApi.create_post(
      content: content,
      platform: task.platform.to_s,
      account_id: pa.peer_account_id,
      media_urls: video_url.present? ? [video_url] : []
    )

    if PostpeerApi.success?(resp)
      task.update!(status: :success, executed_at: Time.current, error_msg: nil)
      { success: true, message: '发布成功' }
    else
      task.update!(status: :failed, executed_at: Time.current, error_msg: resp[:raw].to_s[0, 500])
      { success: false, message: "发布失败：#{resp[:raw].to_s[0, 200]}" }
    end
  end

  # postforme：提交 + 同步轮询结果（最多 60 秒，超时标记 executing）
  def self.publish_postforme(task)
    pa = task.hosting_account.postforme_account
    return { success: false, message: '托管账号未完成 postforme 授权' } unless pa&.authorized?

    resource = task.resource
    return { success: false, message: '成品不存在' } if resource.nil?

    video_url = video_url_for(task, resource)
    content = extract_content(resource)

    resp = PostformeApi.create_post(
      caption: content,
      social_account_ids: [pa.social_account_id],
      media_urls: video_url.present? ? [video_url] : [],
      external_id: "HostingPublishTask:#{task.id}"
    )

    unless PostformeApi.success?(resp)
      task.update!(status: :failed, executed_at: Time.current, error_msg: resp[:raw].to_s[0, 500])
      return { success: false, message: "postforme 发布失败：#{resp[:raw].to_s[0, 200]}" }
    end

    post_id = resp[:body].is_a?(Hash) ? resp[:body]['id'].to_s : ''
    if post_id.blank?
      task.update!(status: :failed, executed_at: Time.current, error_msg: 'postforme 未返回 post ID')
      return { success: false, message: 'postforme 未返回 post ID' }
    end

    result = wait_for_postforme_result(post_id, 60)
    if result.nil?
      task.update!(status: :executing, executed_at: Time.current)
      { success: true, message: "已提交 postforme（post_id=#{post_id}），处理中" }
    elsif result == :success
      task.update!(status: :success, executed_at: Time.current, error_msg: nil)
      { success: true, message: '发布成功' }
    else
      task.update!(status: :failed, executed_at: Time.current, error_msg: result.to_s[0, 500])
      { success: false, message: "发布失败：#{result.to_s[0, 200]}" }
    end
  end

  # x_api：上传视频 + 转码轮询 + 发推
  def self.publish_x_api(task)
    xc = task.hosting_account.x_credential
    return { success: false, message: '托管账号未完成 X 授权' } unless xc&.authorized?

    resource = task.resource
    return { success: false, message: '成品不存在' } if resource.nil?

    video_url = video_url_for(task, resource)
    return { success: false, message: '成品无视频地址' } if video_url.blank?

    token = x_access_token(xc)
    return { success: false, message: '无法获取 X access_token（请重新认证）' } if token.blank?

    content = extract_content(resource)

    # 下载 + 分块上传 + FINALIZE → media_id
    upload = XPublisher.upload_video(token, video_url)
    unless upload[:success]
      task.update!(status: :failed, executed_at: Time.current, error_msg: upload[:message].to_s[0, 500])
      return { success: false, message: "X 上传失败：#{upload[:message]}" }
    end

    media_id = upload[:media_id]

    # 轮询视频转码状态（最多 60 秒）
    state = wait_for_x_media(token, media_id, 60)
    if state == :failed
      task.update!(status: :failed, executed_at: Time.current, error_msg: 'X 视频处理失败')
      return { success: false, message: 'X 视频处理失败' }
    end

    # 发推
    tweet_resp = XApi.create_tweet(access_token: token, text: content, media_ids: [media_id])
    if XApi.success?(tweet_resp)
      tweet_id = tweet_resp[:body].is_a?(Hash) ? tweet_resp[:body].dig('data', 'id').to_s : ''
      task.update!(status: :success, executed_at: Time.current, error_msg: nil)
      { success: true, message: "发布成功（tweet_id=#{tweet_id}）" }
    else
      task.update!(status: :failed, executed_at: Time.current, error_msg: XApi.extract_error(tweet_resp).to_s[0, 500])
      { success: false, message: "X 发推失败：#{XApi.extract_error(tweet_resp)}" }
    end
  end

  # 取托管账号当前有效 X access_token（过期则刷新）
  def self.x_access_token(xc)
    return xc.access_token unless xc.access_token_expired?

    rt = xc.refresh_token
    if rt.blank?
      xc.update!(auth_status: :failed)
      return nil
    end

    resp = XApi.refresh(refresh_token: rt)
    unless XApi.success?(resp)
      xc.update!(auth_status: :failed)
      return nil
    end

    body = resp[:body].is_a?(Hash) ? resp[:body] : {}
    access_token = body['access_token'].to_s
    return nil if access_token.blank?

    expires_in = body['expires_in'].to_i
    xc.update!(
      access_token: access_token,
      refresh_token: body['refresh_token'].presence || rt,
      token_expires_at: expires_in > 0 ? Time.current + expires_in.seconds : nil,
      last_refreshed_at: Time.current
    )
    access_token
  end

  # 同步轮询 postforme 结果，最多 max_wait 秒；返回 :success / 错误信息 / nil（超时）
  def self.wait_for_postforme_result(post_id, max_wait)
    deadline = Time.current + max_wait
    loop do
      resp = PostformeApi.post_result(post_id: post_id)
      if PostformeApi.success?(resp)
        results = PostformeApi.items(resp)
        result = results.find { |r| r['post_id'] == post_id } || results.first
        if result
          return :success if result['success'] == true
          return result['error'].to_s if result['success'] == false
        end
      end
      break if Time.current > deadline
      sleep 10
    end
    nil
  end

  # 同步轮询 X 视频转码状态，最多 max_wait 秒；返回 :done / :failed
  def self.wait_for_x_media(token, media_id, max_wait)
    deadline = Time.current + max_wait
    loop do
      resp = XApi.media_upload_status(access_token: token, media_id: media_id)
      if XApi.success?(resp)
        body = resp[:body].is_a?(Hash) ? resp[:body] : {}
        data = body['data'].is_a?(Hash) ? body['data'] : {}
        info = data['processing_info']
        state = info.is_a?(Hash) ? info['state'].to_s : ''
        return :done if state == 'succeeded' || state == ''
        return :failed if state == 'failed'
      end
      break if Time.current > deadline
      sleep 10
    end
    :done
  end

  # 取成品的视频地址（由 WorkMode 注册表决定 oss_url / video_url）
  def self.video_url_for(task, resource)
    wm = WorkMode.find(task.hosting_account.resource_queue)
    return '' unless wm && wm.video_field.present?
    resource.public_send(wm.video_field).to_s.presence
  end

  # 从资源队列成品提取发布标题/正文
  def self.extract_content(resource)
    return resource.title.to_s if resource.respond_to?(:title) && resource.title.present?
    return resource.description.to_s if resource.respond_to?(:description) && resource.description.present?
    ''
  end
end
