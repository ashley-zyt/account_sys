# == Schema Information
#
# Table name: task_logs
#
#  id                                                   :bigint           not null, primary key
#  error_msg(执行错误信息)                              :text(65535)
#  request_data(请求参数/发送内容)                      :text(65535)
#  response_data(接口返回数据)                          :text(65535)
#  run_at(执行时间)                                     :datetime
#  status(执行结果 success/failed)                      :integer          default("success")
#  task_uuid(关联的任务UUID)                            :string(255)
#  created_at                                           :datetime         not null
#  updated_at                                           :datetime         not null
#  account_id(执行账号ID快照（任务释放后仍保留关联）)   :bigint
#  browser_id(执行浏览器ID快照（任务释放后仍保留关联）) :string(255)
#
# Indexes
#
#  index_task_logs_on_account_id  (account_id)
#  index_task_logs_on_browser_id  (browser_id)
#  index_task_logs_on_run_at      (run_at)
#  index_task_logs_on_status      (status)
#  index_task_logs_on_task_uuid   (task_uuid)
#
class TaskLog < ApplicationRecord
	belongs_to :move_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true
	belongs_to :jianying_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true
	belongs_to :grok_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true
	belongs_to :operation_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true

	# 任务释放后仍然能定位到执行账号/浏览器
	belongs_to :log_account, class_name: 'Account', foreign_key: :account_id, optional: true
	belongs_to :log_browser, class_name: 'Browser', foreign_key: :browser_id, optional: true

	# 获取当前关联的具体任务对象
	def task
		move_task || jianying_task || grok_task || operation_task
	end

	# 获取任务类型
	def task_type
		if move_task.present?
			"搬运任务"
		elsif jianying_task.present?
			"剪映任务"
		elsif grok_task.present?
			"Grok任务"
		elsif operation_task.present?
			"运营任务"
		else
			"未知"
		end
	end

	# 基础校验
	validates :task_uuid, presence: true

	# 日志状态
	enum status: {
		success: 0,
		failed: 1
	}

	# 作用域：获取今日产生的日志
	scope :today, -> {
		where("created_at >= ?", Time.zone.now.beginning_of_day)
	}

	# 获取展示用的账号对象（优先使用快照，避免运营任务释放后关联丢失）
	def display_account
		return log_account if account_id.present?

		if task_uuid == "999"
			begin
				data = eval(response_data)
				Account.find_by(id: data["id"]) if data["id"].present?
			rescue JSON::ParserError, SyntaxError, NameError
				nil
			end
		else
			task&.account
		end
	end

	# 获取展示用的平台名称
	def display_platform
		display_account&.platform || "未知"
	end

	# 获取展示用的浏览器对象（优先使用快照）
	def display_browser
		return log_browser if browser_id.present?

		if task_uuid == "999"
			display_account&.browser
		else
			task&.browser
		end
	end

	ransacker :task_type do
		Arel.sql("CASE WHEN EXISTS (SELECT 1 FROM move_tasks WHERE move_tasks.task_uuid = task_logs.task_uuid) THEN 'move_task' WHEN EXISTS (SELECT 1 FROM jianying_tasks WHERE jianying_tasks.task_uuid = task_logs.task_uuid) THEN 'jianying_task' WHEN EXISTS (SELECT 1 FROM grok_tasks WHERE grok_tasks.task_uuid = task_logs.task_uuid) THEN 'grok_task' WHEN EXISTS (SELECT 1 FROM operation_tasks WHERE operation_tasks.task_uuid = task_logs.task_uuid) THEN 'operation_task' ELSE 'unknown' END")
	end

	# 账号所属平台：优先读取快照字段，回退到关联任务再到 accounts 表
	ransacker :account_platform, formatter: proc { |v| Account.platforms[v] } do
		Arel.sql("COALESCE((SELECT a.platform FROM accounts a WHERE a.id = task_logs.account_id LIMIT 1), (SELECT a.platform FROM move_tasks m JOIN accounts a ON a.id = m.account_id WHERE m.task_uuid = task_logs.task_uuid LIMIT 1), (SELECT a.platform FROM jianying_tasks j JOIN accounts a ON a.id = j.account_id WHERE j.task_uuid = task_logs.task_uuid LIMIT 1), (SELECT a.platform FROM operation_tasks o JOIN accounts a ON a.id = o.account_id WHERE o.task_uuid = task_logs.task_uuid LIMIT 1))")
	end

	def self.ransackable_associations(auth_object = nil)
		%w[move_task jianying_task grok_task operation_task log_account log_browser]
	end

	def self.ransackable_attributes(auth_object = nil)
		%w[
			id
			task_uuid
			request_data
			response_data
			status
			error_msg
			run_at
			account_id
			browser_id
			created_at
			updated_at
			task_type
			account_platform
		]
	end
end
