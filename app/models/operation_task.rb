# == Schema Information
#
# Table name: operation_tasks
#
#  id                                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                 :datetime
#  error_msg(错误信息)                               :text(65535)
#  oss_url(OSS文件地址)                              :string(255)
#  platform(平台)                                    :string(255)
#  start_at(开始时间)                                :datetime
#  status(状态(pending/processing/completed/failed)) :string(255)      default("pending")
#  task_uuid(任务UUID)                               :string(255)
#  theme(主题)                                       :string(255)
#  title(标题)                                       :string(255)
#  created_at                                        :datetime         not null
#  updated_at                                        :datetime         not null
#  account_id(账号ID)                                :bigint
#  browser_id(浏览器ID)                              :string(255)
#  group_id(分组ID)                                  :bigint
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
		pending: 'pending',          # 待发布
		processing: 'processing',    # 处理中
		completed: 'completed',      # 已完成
		failed: 'failed'             # 失败
	}

	enum platform: {
		facebook: 'facebook',
		twitter: 'twitter',
		tiktok: 'tiktok',
		youtube: 'youtube',
		instagram: 'instagram'
	}

	validates :title, presence: true
	validates :oss_url, presence: true
	validates :task_uuid, uniqueness: true, allow_nil: true
	validates :platform, presence: true

	before_validation :generate_task_uuid, on: :create

	scope :pending_for_platform, ->(platform) {
		where(status: :pending, platform: platform).order(created_at: :asc)
	}

	scope :waiting_to_execute, -> {
		where(status: :pending).order(created_at: :asc)
	}

	def self.ransackable_attributes(auth_object = nil)
		%w[id task_uuid oss_url theme title status error_msg start_at actual_publish_time account_id browser_id platform group_id created_at updated_at]
	end

	def self.ransackable_associations(auth_object = nil)
		["account"]
	end

	private

	def generate_task_uuid
		self.task_uuid ||= SecureRandom.uuid
	end
end
