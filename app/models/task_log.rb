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
	has_one :account, through: :move_task
	has_one :browser, through: :move_task

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
				data = JSON.parse(response_data)
				Account.find_by(id: data["id"]) if data["id"].present?
			rescue JSON::ParserError
				nil
			end
		else
			account
		end
	end

	# 获取展示用的平台名称
	def display_platform
		if task_uuid == "999"
			display_account&.platform || "未知"
		else
			move_task&.platform || "未知"
		end
	end

	# 获取展示用的浏览器对象
	def display_browser
		if task_uuid == "999"
			display_account&.browser
		else
			browser
		end
	end

	def self.ransackable_attributes(auth_object = nil)
		%w[
			id
			task_uuid
			account_id
			request_data
			response_data
			status
			error_msg
			run_at
			duration_ms
			created_at
			updated_at
		]
	end
end
