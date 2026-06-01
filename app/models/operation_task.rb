# == Schema Information
#
# Table name: operation_tasks
#
#  id                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间) :datetime
#  description                       :text(65535)
#  error_msg(错误信息)               :text(65535)
#  oss_url(OSS文件地址)              :string(255)
#  platform(平台)                    :string(255)
#  start_at(开始时间)                :datetime
#  status                            :integer          default("pending")
#  task_uuid(任务UUID)               :string(255)
#  theme(主题)                       :string(255)
#  title(标题)                       :string(255)
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  account_id(账号ID)                :bigint
#  browser_id(浏览器ID)              :string(255)
#  group_id(分组ID)                  :bigint
#
# Indexes
#
#  index_operation_tasks_on_account_id              (account_id)
#  index_operation_tasks_on_account_id_and_oss_url  (account_id,oss_url) UNIQUE
#  index_operation_tasks_on_oss_url_and_platform    (oss_url,platform) UNIQUE
#  index_operation_tasks_on_platform                (platform)
#  index_operation_tasks_on_status                  (status)
#  index_operation_tasks_on_task_uuid               (task_uuid) UNIQUE
#

class OperationTask < ApplicationRecord
	belongs_to :account, optional: true

	enum status: {
		pending: 0,          # 待分配账号
		waiting_publish: 1,  # 等待发布
		executing: 2,        # 执行中
		success: 3,          # 成功
		failed: 4            # 失败
	}

	validates :title, presence: true
	validates :oss_url, presence: true
	validates :task_uuid, uniqueness: true, allow_nil: true
	validates :platform, presence: true

	# 非 pending 状态必须有账号
	validates :account_id, presence: true, unless: :pending?

	before_validation :generate_task_uuid, on: :create

	# 作用域：获取可执行任务
	scope :runnable, -> {
		where(status: :waiting_publish)
	}

	# 作用域：按平台筛选待分配任务
	scope :pending_for_platform, ->(platform) {
		where(status: :pending, platform: platform).order(created_at: :asc)
	}

	# 最近任务
	scope :recent, -> {
		order(created_at: :desc)
	}

	# 重置任务到 pending 状态
	def reset_to_pending!
		update!(
			account_id: nil,
			browser_id: nil,
			status: :pending,
			start_at: nil
		)
	end

	def self.ransackable_attributes(auth_object = nil)
		%w[id task_uuid oss_url theme title description status error_msg start_at actual_publish_time account_id browser_id platform group_id created_at updated_at]
	end

	def self.ransackable_associations(auth_object = nil)
		["account"]
	end

	private

	def generate_task_uuid
		self.task_uuid ||= "OP-#{SecureRandom.uuid}"
	end
end
