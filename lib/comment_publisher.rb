# 评论任务下发器：通过机器端指纹浏览器执行评论
#
# 当前机器端尚无「评论」接口，dispatch 为占位实现（返回失败），
# 等机器端新增评论动作后，按下方 TODO 说明实现真实下发即可。
class CommentPublisher
  PORT = 8080

  class << self
    # 下发单条评论任务到机器端（浏览器通道）
    # @param task [CommentTask]
    # @return [Hash] { success: true, task_id: } 或 { success: false, error: }
    def dispatch(task)
      account = task.account
      post    = task.influencer_post

      return { success: false, error: '账号未绑定浏览器' } if account.nil? || account.browser&.machine_ip.blank?
      return { success: false, error: '发文缺失' } if post.nil?

      # TODO: 机器端评论接口未接入。接入后参考 KolOutreachApi.send_single_message 的浏览器通道：
      #   URL:  https://<machine_ip>:8080/accounts/comment
      #   body: { profile_name:, tweet_url:, comment_content:, account_id:, async: true, ref: "comment_task:#{task.id}" }
      #   async 受理：返回 { async: true, task_id: } → 标记 queued + 记录 machine_task_id
      #   回调：机器端执行完回调 /api/v1/browser_tasks/result，ref=comment_task:<id>
      { success: false, error: '机器端评论接口未接入' }
    end
  end
end
