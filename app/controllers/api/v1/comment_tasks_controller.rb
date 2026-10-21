module Api
  module V1
    # 机器端评论任务状态回传接口：机器端执行评论后主动上报结果。
    #
    # POST /api/v1/comment_tasks/result
    # 入参：
    #   task_id : CommentTask 主键 id（也可用 ref=comment_task:<id> 透传定位）
    #   status  : success | failed
    #   message : 失败原因（可选）
    class CommentTasksController < ApplicationController
      skip_before_action :verify_authenticity_token

      def result
        task_id = resolve_task_id
        status  = params[:status].to_s
        message = params[:message].to_s

        if task_id.nil?
          return render json: { type: 'error', message: '缺少有效的 task_id 或 ref' }, status: 400
        end

        render json: BrowserTaskResultHandler.handle_comment(task_id, status, message)
      rescue => e
        Rails.logger.error "[CommentTasks] 评论回传处理异常: #{e.message}"
        render json: { type: 'error', message: e.message }, status: 500
      end

      private

      # 支持两种定位方式：task_id（CommentTask id）或 ref（comment_task:<id>）
      def resolve_task_id
        direct = (params[:task_id] || params[:comment_task_id]).to_s.strip
        return direct.to_i if direct.to_i > 0

        ref = params[:ref].to_s.strip
        return nil unless ref.start_with?('comment_task:')
        id = ref.split(':', 2).last.to_i
        id > 0 ? id : nil
      end
    end
  end
end
