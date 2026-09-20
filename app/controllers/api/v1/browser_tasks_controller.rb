module Api
  module V1
    # 机器端异步浏览器任务完成回调 —— 供机器端在养号/发文/采集/私信/查回复任务真正结束后主动通知结果。
    #
    # 机器端改造说明：所有浏览器任务接口（nurture / fetch_posts / 5 个 publish / send_single_message / check_reply）
    # 加 async:true 后，立即返回 accepted+task_id，后台执行，完成后 POST 本接口通知结果。
    #
    # ref 透传约定（account_sys 下发时生成，机器端原样带回）：
    #   发文任务：<TaskModel>:<id>      如 "MoveTask:123" / "JianyingTask:456"
    #   养号任务：WarmupTask:<id>       如 "WarmupTask:789"
    #   采集任务：Account:<account_id>  如 "Account:234"
    #   发私信：  kol_message:<id>      如 "kol_message:12"
    #   查回复：  kol_contact:<id>      如 "kol_contact:34"
    # 以上 ref 均由 account_sys 下发时生成。若回调未带 ref，或 ref 指向的不是本系统的任务模型，
    # 说明该任务来自外部直接调用（非 account_sys 下发），一律静默忽略并返回 success，不报错。
    class BrowserTasksController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/browser_tasks/result
      # 入参：task_id / profile_name / task_type / status(success|failed) / ref / message / result
      def result
        ref     = params[:ref].to_s.strip
        status  = params[:status].to_s
        message = params[:message].to_s

        # 没有 ref：说明该任务不是 account_sys 下发的（如外部系统/人工直接调用机器端接口后回传结果），
        # 静默忽略即可，不当作错误返回，避免调用方误判、也避免污染日志。
        if ref.blank?
          Rails.logger.info "[BrowserTasks] 回调未携带 ref（task_id=#{params[:task_id]}），判定为非本系统任务，忽略"
          return render json: { type: 'success', message: '未携带 ref，忽略（非本系统任务）' }
        end

        # 更新本地登记记录状态（供后台页面查看 / 超时兜底判断）
        BrowserTaskRecord.mark_result!(params[:task_id].to_s, status, message)

        render json: BrowserTaskResultHandler.process(ref: ref, status: status, message: message, result: params[:result])
      rescue => e
        Rails.logger.error "[BrowserTasks] 回调处理异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { type: 'error', message: e.message }, status: 500
      end
    end
  end
end
