module Api
  module V1
    # 机器端异步浏览器任务完成回调 —— 供机器端在养号/发文/采集任务真正结束后主动通知结果。
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
    class BrowserTasksController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/browser_tasks/result
      # 入参：task_id / profile_name / task_type / status(success|failed) / ref / message / result
      def result
        ref     = params[:ref].to_s.strip
        status  = params[:status].to_s
        message = params[:message].to_s
        task_type = params[:task_type].to_s

        if ref.blank?
          return render json: { type: 'error', message: 'ref 不能为空' }
        end

        model_name, id = ref.split(':', 2)
        id = id.to_i

        case model_name
        when 'WarmupTask'
          handle_warmup(id, status, message)
        when 'Account'
          # 采集：发文数据已由机器端通过 /api/v1/post_stats 回传落库，此处仅记录完成状态
          Rails.logger.info "[BrowserTasks] 采集回调 ref=#{ref} task_type=#{task_type} status=#{status} message=#{message}"
          render json: { type: 'success', message: '已记录采集完成' }
        when 'kol_message'
          handle_kol_send(id, status, message)
        when 'kol_contact'
          handle_kol_reply(id, status, message, params[:result])
        else
          handle_publish(model_name, id, status, message)
        end
      rescue => e
        Rails.logger.error "[BrowserTasks] 回调处理异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { type: 'error', message: e.message }, status: 500
      end

      private

      # 发布任务回调：按模型名 + id 定位任务，复用 TaskReportHelper 更新状态 + 写日志
      def handle_publish(model_name, id, status, message)
        task_model = model_name.safe_constantize
        unless task_model.is_a?(Class) && task_model < ApplicationRecord && WorkMode.for_model(task_model)
          return render json: { type: 'error', message: "未知任务模型: #{model_name}" }
        end

        task = task_model.find_by(id: id)
        return render json: { type: 'success', message: '任务不存在，忽略' } unless task

        snapshot_account_id = task.account_id
        snapshot_browser_id = task.browser_id

        if status == 'success'
          Rails.logger.info "[BrowserTasks] 任务 #{model_name}##{id} 回调成功"
          TaskReportHelper.update_task_status(task, 'success')
          TaskReportHelper.create_task_log(task, 'success', snapshot_account_id, snapshot_browser_id)
        else
          Rails.logger.error "[BrowserTasks] 任务 #{model_name}##{id} 回调失败: #{message}"
          TaskReportHelper.update_task_status(task, 'error', message)
          TaskReportHelper.create_task_log(task, 'error', snapshot_account_id, snapshot_browser_id, message)
        end

        render json: { type: 'success', message: '已更新任务状态' }
      end

      # 养号回调：更新 WarmupTask + warmup_profile
      def handle_warmup(id, status, message)
        warmup_task = WarmupTask.find_by(id: id)
        return render json: { type: 'success', message: '养号任务不存在，忽略' } unless warmup_task

        account = warmup_task.account

        if status == 'success'
          duration_minutes = extract_duration(message)
          warmup_task.update!(status: :success, executed_at: Time.current, error_msg: message, duration_minutes: duration_minutes)
          if account
            profile = account.warmup_profile || account.create_warmup_profile
            profile.update!(last_warmup_at: Time.current, warmup_status: 'success')
          end
          Rails.logger.info "[BrowserTasks] 养号 WarmupTask##{id} 回调成功"
        else
          warmup_task.update!(status: :failed, error_msg: message, executed_at: Time.current)
          if account
            profile = account.warmup_profile || account.create_warmup_profile
            profile.update!(warmup_status: 'failed', last_warmup_at: Time.current)
          end
          Rails.logger.error "[BrowserTasks] 养号 WarmupTask##{id} 回调失败: #{message}"
        end

        render json: { type: 'success', message: '已更新养号任务状态' }
      end

      # 发私信回调：按 KolMessage id 定位，复用 KolOutreachApi.apply_send_result 更新状态
      def handle_kol_send(id, status, message)
        kol_message = KolMessage.find_by(id: id)
        return render json: { type: 'success', message: '私信记录不存在，忽略' } unless kol_message

        KolOutreachApi.apply_send_result(kol_message, success: (status == 'success'), error: message.presence)
        render json: { type: 'success', message: '已更新私信发送状态' }
      end

      # 查回复回调：按 KolContact id 定位，从 result 提取 replies 后复用 apply_reply_result
      def handle_kol_reply(id, status, _message, result)
        contact = KolContact.find_by(id: id)
        return render json: { type: 'success', message: '联系方式不存在，忽略' } unless contact

        return render json: { type: 'success', message: '已记录（无回复）' } unless status == 'success'

        replies = result.is_a?(Hash) ? (result['replies'] || result[:replies]) : nil
        KolOutreachApi.apply_reply_result(contact, replies)
        render json: { type: 'success', message: '已更新回复状态' }
      end

      # 从养号返回信息里提取总时长（秒）→ 分钟，如 "总时长 720 秒, ..."
      def extract_duration(info)
        return nil unless info.to_s =~ /总时长\s*(\d+)\s*秒/
        ($1.to_i / 60.0).round(1)
      end
    end
  end
end
