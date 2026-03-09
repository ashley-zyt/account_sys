# == Schema Information
#
# Table name: jianying_tasks
#
#  id                                                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                                 :datetime
#  error_msg(错误信息/失败原因)                                      :text(65535)
#  oss_url(剪映生成的视频OSS地址)                                   :text(65535)
#  platform(目标发布平台)                                            :integer
#  start_at(任务开始时间)                                            :datetime
#  status(任务状态 pending/waiting_publish/executing/success/failed) :integer          default("pending")
#  task_uuid(任务唯一标识，用于关联日志)                             :string(255)
#  theme(内容主题)                                                   :string(255)
#  title(发布标题)                                                   :text(65535)
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  account_id(发布账号ID)                                            :bigint
#  browser_id(执行任务的浏览器ID)                                    :bigint
#  group_id(任务组ID)                                                :string(255)
#
# Indexes
#
#  index_jianying_tasks_on_account_id  (account_id)
#  index_jianying_tasks_on_browser_id  (browser_id)
#  index_jianying_tasks_on_group_id    (group_id)
#  index_jianying_tasks_on_platform    (platform)
#  index_jianying_tasks_on_status      (status)
#  index_jianying_tasks_on_task_uuid   (task_uuid) UNIQUE
#  index_jianying_tasks_on_theme       (theme)
#
class JianyingTask < ApplicationRecord
	belongs_to :browser, optional: true
	belongs_to :account, optional: true

	enum status: {
		pending: 0,          # 待分配账号
		waiting_publish: 1,  # 等待发布
		executing: 2,        # 执行中
		success: 3,          # 成功
		failed: 4            # 失败
	}

	# 平台枚举（与 Account.platform 一致）
	enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4
	}

	validates :task_uuid, presence: true, uniqueness: true
	validates :oss_url, presence: true
	validates :platform, presence: true
	validates :theme, presence: true

	# 非 pending 状态必须有账号
	validates :account_id, presence: true, unless: :pending?

	before_validation :generate_task_uuid, on: :create

	# 作用域：获取可执行任务
	scope :runnable, -> {
		where(status: :waiting_publish)
	}

	# 作用域：按主题筛选待分配任务
	scope :pending_for_theme, ->(theme) {
		where(status: :pending, theme: theme).order(created_at: :asc)
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

	# Ransack 搜索允许的字段
	def self.ransackable_attributes(auth_object = nil)
		%w[id task_uuid oss_url theme title status error_msg start_at actual_publish_time account_id browser_id platform group_id created_at updated_at]
	end

	def self.ransackable_associations(auth_object = nil)
		%w[account browser]
	end

	private

	def generate_task_uuid
		self.task_uuid ||= "JY-#{SecureRandom.uuid}"
	end
end
