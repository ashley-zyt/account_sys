# postforme 发布执行器。
#
# 走 postforme 渠道的任务，提交发布到 postforme 平台（异步）：
#   调 create_post 提交（caption + media + social_account）→ 拿到 post_id → 记录 PostformePost(processing)。
# 发布结果不在这里回写，由 PostformeStatusPoller 轮询后回写任务 success/failed。
module PostformePublisher
  # 提交发布任务到 postforme
  # @param task [Object] 本系统任务实例（MoveTask/HunjianTask/JianyingTask 等）
  # @return [Hash] { success:, message:, post_id: }
  def self.publish(task)
    pa = task.account&.postforme_account
    return { success: false, message: '账号未授权 postforme，无法发布' } unless pa&.authorized?

    media_urls = XPublisher.media_urls_for(task)

    caption = caption_for(task)
    # 数字货币主题：postforme 用 caption，统一追加免责声明
    caption = FinancialDisclaimer.append(caption) if FinancialDisclaimer.applies_to?(task.theme)

    resp = PostformeApi.create_post(
      caption: caption,
      social_account_ids: [pa.social_account_id],
      media_urls: media_urls,
      external_id: "#{task.class.name}:#{task.id}"
    )

    unless PostformeApi.success?(resp)
      return { success: false, message: "postforme 发布失败：#{resp[:raw]}" }
    end

    post_id = resp[:body]['id'].to_s
    return { success: false, message: 'postforme 未返回 post ID' } if post_id.blank?

    PostformePost.create!(
      task: task,
      post_id: post_id,
      status: :processing,
      social_account_id: pa.social_account_id
    )

    { success: true, message: "已提交 postforme（post_id=#{post_id}）", post_id: post_id }
  end

  # 正文：外部资源任务优先用完整 text（图文/纯文字），旧视频任务用 title
  def self.caption_for(task)
    if task.respond_to?(:text) && task.text.present?
      task.text
    else
      task.title.to_s
    end
  end
end
