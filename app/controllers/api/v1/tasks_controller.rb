module Api
	module V1
		class TasksController < ApplicationController
			skip_before_action :verify_authenticity_token, only: [:report]

			def fetch_next_executable_task
				loop do
					# candidate_id = MoveTask.with_account_unused_today.limit(1).pluck(:id).first
					# return render json: {id: nil,video_url: nil,social_account_id: nil,adspower_user_name: nil,account_type: nil,title: nil} unless candidate_id

					# today_begin = Time.current.beginning_of_day
    	# 			used_account_ids = MoveTask.where(start_at: today_begin..).distinct.pluck(:account_id).compact
    	# 			if used_account_ids.empty?
					# 	affected = MoveTask.where(id: candidate_id, status: :waiting_publish).update_all(status: :executing,start_at: Time.current,updated_at: Time.current)
					# else
					# 	affected = MoveTask.where(id: candidate_id, status: :waiting_publish).where.not(account_id: used_account_ids).update_all(status: :executing,start_at: Time.current,updated_at: Time.current)
					# end

					# next if affected.zero?
					
					# task = MoveTask.find(candidate_id)

					task = MoveTask.find(2)
					return render json: {id: task.id,video_url: task.video_url,social_account_id: task.source_account_url,adspower_user_name: task.browser.profile_name,account_type: task.platform,title: task.title}
				end
			end
			def report
				task_id = params[:id].to_s.strip
				status    = params[:status].to_s.strip

				return render json: {type: 'error', message: "task_id不能为空" } if task_id.blank?
				return render json: {type: 'error', message: "status不能为空" } if status.blank?

				task = MoveTask.find_by(id: task_id)
				# return not_found('任务不存在') unless task
				return render json: {type: 'error', message: "任务不存在" } unless task

				unless %w[success error].include?(status)
					# return bad_request('status必须为 success 或 error')
					return render json: {type: 'error', message: "更新成功" }
				end

				ActiveRecord::Base.transaction do
					update_task_status!(task, status)
					create_task_log!(task, status)
				end
				return render json: {type: '上报成功', message: "更新成功" }
				
			end
			def update_task_status!(task, status)

				if status == 'success'
					task.update!(
						status: :success,
						actual_publish_time: Time.current,
						error_msg: nil
					)

				else
					# task.increment!(:retry_count)

					task.update!(
						status: :failed,
						error_msg: params[:status_desp]
					)
				end
			end
			def create_task_log!(task, status)
				if status == 'success'
					task_status = "success"
				else
					task_status = "failed"
				end
				TaskLog.create!(
					task_uuid: task.task_uuid,
					response_data: params.to_s,
					status: task_status,
					error_msg: params[:status_desp],
					run_at: Time.current
				)
			end
		end
	end
end