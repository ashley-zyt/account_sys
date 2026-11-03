class Admin::TaskLogsController < Admin::BaseController
	def index
		@q = TaskLog.ransack(params[:q])
		task_associations = WorkMode.resource_modes.map { |m| { m.singular_association_name => [:account, :browser] } }
		@task_logs = @q.result(distinct: true)
		               .includes(*task_associations)
		               .order(run_at: :desc)
		               .page(params[:page])
		               .per(15)
		@work_types = Account.work_types.keys
	end

	def show
		@task_log = TaskLog.find(params[:id])
	end

	# 今日发布状况弹窗：统计各平台正常账号数、今日最终成功/失败，及最终失败账号列表
	def publish_status
		@summary = PublishDailySummary.compute(Date.today)
		render layout: false
	end

	# 重试失败任务（任务日志页「重试」按钮），两种模式：
	#   常规（mode 为空）：原失败任务仍处于 failed → 重置回 pending 并立即重新分配 + 下发（内容相同）。
	#   换资源（mode=fresh）：原资源已被其它任务使用（状态已不是 failed）→ 给原失败账号分配一条新资源立即发布。
	# 防重复：该账号当天已发布成功则禁止重试；「资源失效」的任务重试也注定失败，一并拦截。
	def republish
		@task_log = TaskLog.find(params[:id])
		task = @task_log.task

		if task.nil?
			redirect_back fallback_location: admin_task_logs_path, alert: "该日志未关联到资源队列任务，无法重试"
			return
		end

		account = @task_log.display_account
		today_range = Date.today.beginning_of_day..Date.today.end_of_day
		account_done = account.present? &&
		               task.class.exists?(account_id: account.id, status: :success, actual_publish_time: today_range)

		if params[:mode].to_s == 'fresh'
			# 换资源重试：原资源已被使用，给原失败账号换一条新资源发布
			if account.nil?
				redirect_back fallback_location: admin_task_logs_path, alert: "无法定位该日志的执行账号，无法换资源重试"
				return
			end
			if account_done
				redirect_back fallback_location: admin_task_logs_path, alert: "账号「#{account.account_name}」当天已发布成功，无需重试"
				return
			end

			account_id   = account.id
			account_name = account.account_name
			Thread.new do
				ActiveRecord::Base.connection_pool.with_connection do
					begin
						result = PublishScheduler.publish_for_account(account_id)
						Rails.logger.info "[TaskLogs] 换资源重试账号 #{account_name}(#{account_id}): #{result[:message]}"
					rescue => e
						Rails.logger.error "[TaskLogs] 换资源重试账号 #{account_name}(#{account_id}) 异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
					end
				end
			end

			redirect_back fallback_location: admin_task_logs_path,
			              notice: "已为账号「#{account_name}」换一条新资源重新发布，后台执行中，请稍后刷新查看"
		else
			# 常规重试：重置同一条失败资源回 pending，重新分配 + 下发
			if task.status.to_s != 'failed'
				redirect_back fallback_location: admin_task_logs_path,
				              alert: "任务 ##{task.id} 的资源已被使用（当前状态 #{task.status}），请使用「换资源重试」"
				return
			end

			if task.error_msg.to_s.include?('资源失效')
				redirect_back fallback_location: admin_task_logs_path, alert: "任务 ##{task.id} 因资源失效失败，重试也无法成功，已跳过"
				return
			end

			if account_done
				redirect_back fallback_location: admin_task_logs_path, alert: "账号「#{account.account_name}」当天已发布成功，无需重试"
				return
			end

			platform  = task.platform.to_s
			theme     = task.theme.to_s
			task_id   = task.id
			task_name = task.class.name

			# 重置回 pending（同一条内容重试）
			task.update_columns(
				status: task.class.statuses[:pending],
				account_id: nil,
				browser_id: nil,
				failure_count: 0,
				error_msg: nil,
				start_at: nil,
				updated_at: Time.current
			)

			# 立即重新分配 + 下发（后台线程，接口即时返回）
			Thread.new do
				ActiveRecord::Base.connection_pool.with_connection do
					begin
						TaskScheduler.assign_resources(platform: platform, only_combos: [[platform, theme]], redirect_logger: false)
						to_publish = PublishScheduler.fetch_all_tasks(platform: platform)
						                              .select { |t| t.platform.to_s == platform && t.theme.to_s == theme }
						PublishScheduler.run_tasks_with_pool(to_publish) if to_publish.any?
						Rails.logger.info "[TaskLogs] 重试任务 #{task_name}##{task_id} 完成：平台 #{platform}/主题 #{theme}，下发 #{to_publish.size} 条"
					rescue => e
						Rails.logger.error "[TaskLogs] 重试任务 #{task_name}##{task_id} 异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
					end
				end
			end

			redirect_back fallback_location: admin_task_logs_path,
			              notice: "已重置任务 ##{task_id}（#{task_name}）回待分配并重新下发发布，后台执行中，请稍后刷新查看"
		end
	end
end
