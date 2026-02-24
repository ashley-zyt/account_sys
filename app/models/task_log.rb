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

	# 基础校验
	validates :task_uuid, presence: true

	# 日志状态
	enum status: {
		success: 0,
		failed: 1
	}

	# 最近日志
	scope :recent, -> {
		order(run_at: :desc)
	}

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
