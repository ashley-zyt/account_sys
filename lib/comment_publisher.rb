# 评论任务下发器：通过机器端指纹浏览器执行评论
#
# 机器端接口：POST /twitter/comment（HTTPS，同机 nginx 反代）
# 异步受理：async:true + ref=comment_task:<id>，机器端立即返回 accepted+task_id，
# 执行完成后回传 /api/v1/comment_tasks/result。
require 'json'

class CommentPublisher
  class << self
    # 下发单条评论任务到机器端（浏览器通道，异步受理）
    # @param task [CommentTask]
    # @return [Hash] { success: true, task_id: } 或 { success: false, error: }
    def dispatch(task)
      account = task.account
      post    = task.influencer_post

      return { success: false, error: '账号未绑定浏览器' } if account.nil? || account.browser&.machine_ip.blank?
      return { success: false, error: '账号浏览器缺 profile_name' } if account.browser&.profile_name.blank?
      return { success: false, error: '发文缺失' } if post.nil?
      return { success: false, error: '发文链接缺失' } if post.source_url.blank?

      url = "https://#{account.browser.machine_ip}/twitter/comment"
      body = {
        profile_name: account.browser.profile_name,
        platform: 'twitter',
        target_url: post.source_url,
        comment_content: task.comment_content,
        account_id: account.id,
        async: true,
        ref: "comment_task:#{task.id}"
      }

      response = RemoteApiClient.post(url, body, read_timeout: 30)
      accepted = parse_accepted(response)

      if accepted
        { success: true, task_id: accepted['task_id'] }
      else
        { success: false, error: extract_error(response) }
      end
    rescue => e
      Rails.logger.error "[CommentPublisher] 下发评论任务 #{task.id} 异常: #{e.message}"
      { success: false, error: e.message }
    end

    private

    # 判断响应是否为「异步受理」，是则返回解析后的 data（含 task_id），否则返回 nil
    def parse_accepted(response)
      return nil unless response && response.code.to_i == 200
      data = JSON.parse(response.body)
      data['type'] == 'accepted' ? data : nil
    rescue JSON::ParserError
      nil
    end

    # 提取失败原因（同步模式 type=error 或非 200 响应）
    def extract_error(response)
      return "机器端无响应或 HTTP #{response&.code}" unless response && response.code.to_i == 200
      data = JSON.parse(response.body) rescue {}
      data['error_info'].presence || data['status'].presence || data['type'].presence || '未知错误'
    end
  end
end
