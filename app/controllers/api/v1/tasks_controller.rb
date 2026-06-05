module Api
	module V1
		class TasksController < ApplicationController
			skip_before_action :verify_authenticity_token, only: [:report]

			def fetch_next_executable_task
				# next_task = MoveTask.find(19081)
				next_task = MoveTask.where(status:"waiting_publish").where("account_id is not null").first
				if next_task.nil?
					Account.active.where(work_type:0).each do |account|
						task = MoveTask.where(status:"pending").where(platform:account.platform,theme:account["theme"]).order("created_at asc").first
						if !task.nil?
							task.update(account_id: account.id,browser_id: account.browser_id,status:"waiting_publish")
						end
					end
				end
				return render json: {id: nil,video_url: nil,social_account_id: nil,adspower_user_name: nil,account_type: nil,title: nil} if next_task.nil?
				id = next_task.id
				next_task.update(status:"executing")
				next_task = MoveTask.find_by(id:id)
				return render json: {id: next_task.id,video_url: next_task.video_url,social_account_id: next_task.source_account_url,adspower_user_name: next_task.browser.profile_name,account_type: next_task.platform,title: next_task.title}
			end

			def fetch_operation_task
				# next_task = OperationTask.find(179)
				next_task = OperationTask.where(status: :waiting_publish)
				                        .where("account_id IS NOT NULL")
				                        .order(created_at: :asc)
				                        .first

				if next_task.nil?
					return render json: {
						type: 'error',
						message: '暂无待发布的运营任务'
					}
				end

				task_id = next_task.id
				next_task.update!(status: :executing, start_at: Time.current)

				return render json: {
					type: 'success',
					data: {
						id: next_task.id,
						task_uuid: next_task.task_uuid,
						oss_url: next_task.oss_url,
						title: next_task.title,
						description: next_task.description,
						theme: next_task.theme,
						platform: next_task.platform,
						account_id: next_task.account_id,
						browser_id: next_task.browser_id,
						account_name: next_task.account&.account_name,
						browser_name: next_task.browser&.profile_name
					}
				}
			end

			def report
				task_type = params[:task_type].to_s.strip
				task_id = params[:id].to_s.strip
				status    = params[:status].to_s.strip

				return render json: {type: 'error', message: "task_type不能为空" } if task_type.blank?
				return render json: {type: 'error', message: "task_id不能为空" } if task_id.blank?
				return render json: {type: 'error', message: "status不能为空" } if status.blank?

				unless %w[move operation jianying].include?(task_type)
					return render json: {type: 'error', message: "task_type必须为 move、operation 或 jianying" }
				end

				task = find_task_by_type_and_id(task_type, task_id)
				return render json: {type: 'error', message: "任务不存在" } unless task

				unless %w[success error].include?(status)
					return render json: {type: 'error', message: "状态必须为 success 或 error" }
				end

				ActiveRecord::Base.transaction do
					# 先快照执行时的账号/浏览器，避免后续运营任务释放资源后丢失关联
					snapshot_account_id = task.account_id
					snapshot_browser_id = task.browser_id

					update_task_status!(task, status)
					create_task_log!(task, status, snapshot_account_id, snapshot_browser_id)
				end
				return render json: {type: 'success', message: "更新成功" }
			end

			private

			def find_task_by_type_and_id(task_type, task_id)
				case task_type
				when 'move'
					MoveTask.find_by(id: task_id)
				when 'operation'
					OperationTask.find_by(id: task_id)
				when 'jianying'
					JianyingTask.find_by(id: task_id)
				else
					nil
				end
			end

			def update_task_status!(task, status)
				if status == 'success'
					task.update!(
						status: :success,
						actual_publish_time: Time.current,
						error_msg: nil
					)
				else
					if task.is_a?(OperationTask)
						task.update!(
							status: :pending,
							account_id: nil,
							error_msg: nil,
							start_at: nil
						)
					else
						task.update!(
							status: :failed,
							error_msg: params[:status_desp]
						)
					end
				end
			end

			def create_task_log!(task, status, snapshot_account_id = nil, snapshot_browser_id = nil)
				task_status = status == 'success' ? "success" : "failed"

				TaskLog.create!(
					task_uuid: task.task_uuid,
					account_id: snapshot_account_id,
					browser_id: snapshot_browser_id,
					response_data: params.to_s,
					status: task_status,
					error_msg: params[:status_desp],
					run_at: Time.current
				)

				if params[:status_desp].present? && (
					params[:status_desp].include?("not logged in") ||
					params[:status_desp].include?("account verification") ||
					params[:status_desp].include?("some of your media failed to upload") ||
					params[:status_desp].include?("account banned or human verification required") ||
					params[:status_desp].include?("account verification required after upload")
				)
					Account.where(id: snapshot_account_id).update_all(status: 2)
				end
			end
		end
	end
end