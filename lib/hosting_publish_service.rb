# 客户托管发布服务：从资源队列取成品生成托管发布任务（手动触发）。
#
# 取成品规则：按托管账号指定的「资源队列 + 主题 + 平台」取一条未消费、非终态的成品，
# 生成 hosting_publish_tasks，并通过 resource_type + resource_id 唯一索引避免重复发。
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

  # 执行发布：调用 postpeer 发布该托管发布任务对应的成品，并回写结果
  # @return [Hash] { success:, message: }
  def self.publish(task)
    hosting_account = task.hosting_account
    pa = hosting_account.postpeer_account
    return { success: false, message: '托管账号未完成 postpeer 授权' } unless pa&.authorized?

    wm = WorkMode.find(hosting_account.resource_queue)
    resource = task.resource
    return { success: false, message: '成品不存在' } if resource.nil?

    video_url = wm && wm.video_field.present? ? resource.public_send(wm.video_field).to_s : ''
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

  # 从资源队列成品提取发布标题/正文
  def self.extract_content(resource)
    return resource.title.to_s if resource.respond_to?(:title) && resource.title.present?
    return resource.description.to_s if resource.respond_to?(:description) && resource.description.present?
    ''
  end
end
