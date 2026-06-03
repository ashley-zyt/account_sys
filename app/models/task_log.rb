# == Schema Information
#
# Table name: task_logs
#
#  id                              :bigint           not null, primary key
#  error_msg(执行错误信息)         :text(65535)
#  request_data(请求参数/发送内容) :text(65535)
#  response_data(接口返回数据)     :text(65535)
#  run_at(执行时间)                :datetime
#  status(执行结果 success/failed) :integer          default("success")
#  task_uuid(关联的任务UUID)       :string(255)
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#
# Indexes
#
#  index_task_logs_on_run_at     (run_at)
#  index_task_logs_on_status     (status)
#  index_task_logs_on_task_uuid  (task_uuid)
#
class TaskLog < ApplicationRecord
	belongs_to :move_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true
	belongs_to :jianying_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true
	belongs_to :operation_task, foreign_key: :task_uuid, primary_key: :task_uuid, optional: true

	# 获取当前关联的具体任务对象
	def task
		move_task || jianying_task || operation_task
	end

	# 获取任务类型
	def task_type
		if move_task.present?
			"搬运任务"
		elsif jianying_task.present?
			"剪映任务"
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

	# 获取展示用的账号对象
	def display_account
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
		if task_uuid == "999"
			display_account&.platform || "未知"
		else
			task&.platform || "未知"
		end
	end

	# 获取展示用的浏览器对象
	def display_browser
		if task_uuid == "999"
			display_account&.browser
		else
			task&.browser
		end
	end

	ransacker :task_type do
		Arel.sql("CASE WHEN EXISTS (SELECT 1 FROM move_tasks WHERE move_tasks.task_uuid = task_logs.task_uuid) THEN 'move_task' WHEN EXISTS (SELECT 1 FROM jianying_tasks WHERE jianying_tasks.task_uuid = task_logs.task_uuid) THEN 'jianying_task' WHEN EXISTS (SELECT 1 FROM operation_tasks WHERE operation_tasks.task_uuid = task_logs.task_uuid) THEN 'operation_task' ELSE 'unknown' END")
	end

	def self.ransackable_associations(auth_object = nil)
		%w[move_task jianying_task operation_task]
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
			created_at
			updated_at
			task_type
		]
	end
end
