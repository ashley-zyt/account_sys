class TaskScheduler
	def self.pending_task
		# 分配今日资源
		Account.active.where(work_type:0).each do |account|
			task = MoveTask.where(status:"pending").where(platform:account.platform,theme:account["theme"]).order("created_at asc").first
			if !task.nil?
				task.update(account_id: account.id,browser_id: account.browser_id,status:"waiting_publish")
			end
		end
	end

	def self.assign_operation_resources
		today = Date.today
		today_start = today.beginning_of_day
		today_end = today.end_of_day

		Account.active.where(work_type: "人工运营").each do |account|
			has_posted_today = OperationTask.exists?(
				account_id: account.id,
				status: :success,
				actual_publish_time: today_start..today_end
			)

			next if has_posted_today

			pending_task = OperationTask.where(status: :pending, platform: account.platform, theme: account.theme).order(created_at: :asc).first

			if pending_task
				ActiveRecord::Base.transaction do
					pending_task.update!(
						account_id: account.id,
						browser_id: account.browser_id,
						status: :waiting_publish
					)
				end
				Rails.logger.info "人工运营账号 #{account.account_name}[#{account.platform}-#{account.theme}] 分配运营资源成功"
			else
				Rails.logger.warn "人工运营账号 #{account.account_name}[#{account.platform}-#{account.theme}] 暂无可用运营资源"
			end
		end
	end

	# 找出待执行任务中与锁定接口重合的指纹浏览器名称
	def self.find_locked_browsers_in_pending_tasks
		require 'net/http'
		require 'json'

		# 1. 获取待执行任务中的指纹浏览器名称
		pending_browser_ids = []

		# 从搬运任务中获取
		# pending_browser_ids += MoveTask.where(status: :pending).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 从运营任务中获取
		pending_browser_ids += OperationTask.where(status: :pending).where.not(browser_id: nil).pluck(:browser_id).uniq

		# 获取浏览器名称
		pending_browser_names = Browser.where(id: pending_browser_ids.uniq).pluck(:profile_name).uniq

		return { pending_browsers: pending_browser_names, locked_browsers: [], matched_browsers: [] } if pending_browser_names.empty?

		# 2. 调用锁定接口获取锁定的浏览器列表
		begin
			uri = URI('http://174.139.46.117:8080/api/browser/locked')
			http = Net::HTTP.new(uri.host, uri.port)
			http.open_timeout = 10
			http.read_timeout = 10

			response = http.get(uri.path)
			locked_data = JSON.parse(response.body)

			# 提取锁定的浏览器名称
			locked_browser_names = if locked_data.is_a?(Array)
				locked_data.map { |item| item['name'] || item[:name] }.compact
			elsif locked_data.is_a?(Hash) && locked_data['data'].is_a?(Array)
				locked_data['data'].map { |item| item['name'] || item[:name] }.compact
			else
				[]
			end

			# 3. 找出重合的浏览器名称
			matched_browser_names = pending_browser_names & locked_browser_names

			{
				pending_browsers: pending_browser_names,
				locked_browsers: locked_browser_names,
				matched_browsers: matched_browser_names
			}
		rescue => e
			Rails.logger.error "调用锁定浏览器接口失败: #{e.message}"
			{
				pending_browsers: pending_browser_names,
				locked_browsers: [],
				matched_browsers: [],
				error: e.message
			}
		end
	end
end