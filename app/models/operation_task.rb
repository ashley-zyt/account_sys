# == Schema Information
#
# Table name: operation_tasks
#
#  id                   :bigint           not null, primary key
#  theme                :string(255)      comment('主题')
#  title                :string(255)      comment('标题')
#  oss_url              :string(255)      comment('OSS文件地址')
#  account_id           :bigint           comment('账号ID')
#  status               :string(255)      default('pending'), comment('状态(pending/processing/completed/failed)')
#  error_msg            :text(65535)      comment('错误信息')
#  start_at             :datetime         comment('开始时间')
#  actual_publish_time  :datetime         comment('实际发布时间')
#  browser_id           :string(255)      comment('浏览器ID')
#  platform             :string(255)      comment('平台')
#  group_id             :bigint           comment('分组ID')
#  task_uuid            :string(255)      comment('任务UUID')
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
# Indexes
#
#  index_operation_tasks_on_account_id                           (account_id)
#  index_operation_tasks_on_platform                            (platform)
#  index_operation_tasks_on_status                              (status)
#  index_operation_tasks_on_task_uuid                           (task_uuid) UNIQUE
#  index_operation_tasks_on_oss_url_and_platform                (oss_url,platform) UNIQUE
#  index_operation_tasks_on_account_id_and_oss_url              (account_id,oss_url) UNIQUE
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