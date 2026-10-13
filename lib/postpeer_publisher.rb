# postpeer 发布执行器。
#
# 走 postpeer 渠道的任务，提交发布到 postpeer 平台：
#   调 create_post 提交（content + platforms + mediaItems）→ 拿到 postId → 记录 PostpeerPost(processing)。
# 发布结果不在这里回写，由 PostpeerStatusPoller 轮询后回写任务 success/failed。
module PostpeerPublisher
  # 提交发布任务到 postpeer
  # @param task [Object] 本系统任务实例（MoveTask/HunjianTask/JianyingTask 等）
  # @return [Hash] { success:, message:, post_id: }
  def self.publish(task)
    pa = task.account&.postpeer_account
    return { success: false, message: '账号未授权 postpeer，无法发布' } unless pa&.authorized?

    # 视频地址字段由注册表决定（oss_url / video_url）
    mode = WorkMode.for_model(task.class)
    video_url = (mode && mode.video_field.present?) ? task.public_send(mode.video_field) : nil
    media_urls = video_url.present? ? [video_url.to_s] : []

    caption = task.title.to_s
    # 数字货币主题：postpeer 用 content（=title），统一追加免责声明
    caption = FinancialDisclaimer.append(caption) if FinancialDisclaimer.applies_to?(task.theme)

    resp = PostpeerApi.create_post(
      content: caption,
      platform: task.platform,
      account_id: pa.peer_account_id,
      media_urls: media_urls
    )

    unless PostpeerApi.success?(resp)
      return { success: false, message: "postpeer 发布失败：#{resp[:raw]}" }
    end

    post_id = resp[:body].is_a?(Hash) ? resp[:body]['postId'].to_s : ''
    return { success: false, message: 'postpeer 未返回 post ID' } if post_id.blank?

    PostpeerPost.create!(
      task: task,
      post_id: post_id,
      status: :processing,
      peer_account_id: pa.peer_account_id
    )

    { success: true, message: "已提交 postpeer（post_id=#{post_id}）", post_id: post_id }
  end
end
