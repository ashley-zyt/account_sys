module Api
	module V1
		class TasksController < ApplicationController
			skip_before_action :verify_authenticity_token, only: [:report]

			def fetch_next_executable_task
				loop do
					# 1. 选取一个候选任务 ID
					candidate_id = MoveTask.with_account_unused_today.limit(1).pluck(:id).first
					return render json: {id: nil,video_url: nil,social_account_id: nil,adspower_user_name: nil,account_type: nil,title: nil} unless candidate_id

					# 2. 原子更新：仅当状态仍是 waiting_publish 且账号今日未占用
					# affected = MoveTask.where(id: candidate_id, status: :waiting_publish).where.not(account_id: Account.joins(:move_tasks).where(move_tasks: { start_at: MoveTask::TODAY_BEGINNING.. }).distinct.select(:id)).update_all(status: :executing,start_at: Time.current,updated_at: Time.current)
					today_begin = Time.current.beginning_of_day
    				used_account_ids = MoveTask.where(start_at: today_begin..).distinct.pluck(:account_id).compact
    				if used_account_ids.empty?
						affected = MoveTask.where(id: candidate_id, status: :waiting_publish).update_all(status: :executing,start_at: Time.current,updated_at: Time.current)
					else
						# 使用 NOT IN 但要避免子查询引用同一张表，这里直接传数组
						affected = MoveTask.where(id: candidate_id, status: :waiting_publish).where.not(account_id: used_account_ids).update_all(status: :executing,start_at: Time.current,updated_at: Time.current)
					end

					next if affected.zero?  # 更新失败，重试下一个

					# 3. 重新加载任务
					
					task = MoveTask.find(candidate_id)
					return render json: {id: task.id,video_url: task.video_url,social_account_id: task.source_account_url,adspower_user_name: task.browser.profile_name,account_type: task.platform,title: task.title}
				end
			end
			def report
				task_id = params[:id].to_s.strip
				status    = params[:status].to_s.strip

				return bad_request('task_id不能为空') if task_uuid.blank?
				return bad_request('status不能为空') if status.blank?

				task = MoveTask.find_by(id: task_id)
				return not_found('任务不存在') unless task

				unless %w[success failed].include?(status)
					return bad_request('status必须为 success 或 failed')
				end

				ActiveRecord::Base.transaction do
					update_task_status!(task, status)
					create_task_log!(task, status)
				end

				render json: {
					code: 200,
					msg: '上报成功',
					task_uuid: task.task_uuid,
					status: task.status
				}
			end
			def update_task_status!(task, status)
				now = Time.current

				if status == 'success'
					task.update!(
						status: :success,
						actual_publish_time: now,
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
				TaskLog.create!(
					task_uuid: task.task_uuid,
					response_data: params.to_s,
					status: status,
					error_msg: params[:status_desp],
					run_at: now
				)
			end
		end
	end
end