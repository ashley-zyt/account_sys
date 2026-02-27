# == Schema Information
#
# Table name: move_tasks
#
#  id                                                                :bigint           not null, primary key
#  actual_publish_time(实际发布时间)                                 :datetime
#  error_msg(错误信息/失败原因)                                      :text(65535)
#  platform(目标发布平台)                                            :integer
#  source_account_url(来源账号主页链接)                              :string(255)
#  start_at(任务开始时间)                                            :datetime
#  status(任务状态 pending/waiting_publish/executing/success/failed) :integer          default("pending")
#  task_uuid(任务唯一标识，用于关联日志)                             :string(255)
#  theme(内容主题)                                                   :string(255)
#  title(发布标题)                                                   :text(65535)
#  video_url(源视频地址)                                             :string(255)
#  created_at                                                        :datetime         not null
#  updated_at                                                        :datetime         not null
#  account_id(发布账号ID)                                            :bigint
#  browser_id(执行任务的浏览器ID)                                    :bigint
#  group_id(任务组ID，同一视频的多平台任务共享)                      :string(255)
#
# Indexes
#
#  idx_move_tasks_video_platform   (video_url,platform) UNIQUE
#  idx_tasks_status_created        (status,created_at)
#  idx_tasks_theme_status          (theme,status)
#  index_move_tasks_on_browser_id  (browser_id)
#  index_move_tasks_on_group_id    (group_id)
#  index_move_tasks_on_platform    (platform)
#  index_move_tasks_on_status      (status)
#  index_move_tasks_on_task_uuid   (task_uuid) UNIQUE
#
class MoveTask < ApplicationRecord
	belongs_to :browser, optional: true
	belongs_to :account, optional: true


	enum status: {
		pending: 0,          # 待分配账号
		waiting_publish: 1,  # 等待发布
		executing: 2,        # 执行中
		success: 3,          # 成功
		failed: 4            # 失败
	}
	# 平台枚举（与 Account.platform 完全一致）
	enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		# instagram: 5
	}

	validates :task_uuid, presence: true, uniqueness: true
	validates :video_url, presence: true


	# 非 pending 状态必须有账号
	validates :account_id, presence: true, unless: :pending?

	validates :platform, presence: true
	validates :group_id, presence: true
	validates :video_url, uniqueness: { scope: :platform, message: '该视频在此平台已存在任务' }

	before_validation :generate_task_uuid, on: :create


	scope :runnable, -> {
		where(status: [:waiting_publish])
	}

	# 作用域：按目标平台筛选待分配任务
	scope :pending_for_platform, ->(platform) {
		where(status: :pending, platform: platform).order(created_at: :asc)
	}

	before_validation :assign_group_id, on: :create

	TODAY_BEGINNING = Time.current.beginning_of_day
	# 待执行任务（按先进先出）
	scope :waiting_to_execute, -> {
		where(status: :waiting_publish).order(created_at: :asc)
	}

	# 筛选出「账号今日未占用」的待执行任务
	scope :with_account_unused_today, -> {
		waiting_to_execute.where.not(account_id: Account.joins(:move_tasks).where(move_tasks: { start_at: TODAY_BEGINNING.. }).distinct.select(:id))
	}

	# 重置任务到 pending 状态（清空账号信息）
	def reset_to_pending!
		update!(
			account_id: nil,
			browser_id: nil,
			status: :pending,
			start_at: nil    # 清空开始时间，因为是重新分配
		)
	end

	def self.ransackable_attributes(auth_object = nil)
		%w[
			id
			task_uuid
			video_url
			source_account_url
			theme
			title
			platform
			account_id
			browser_id
			status
			error_msg
			start_at
			actual_publish_time
			retry_count
			group_id
			created_at
			updated_at
		]
	end
	 # Ransack 搜索允许的关联
	def self.ransackable_associations(auth_object = nil)
		["account", "browser"]
	end

	# 如果你还想限制搜索字段（可选）
	def self.ransackable_attributes(auth_object = nil)
		["id", "video_url", "source_account_url", "theme", "title", "platform", "status", "group_id", "start_at", "actual_publish_time", "retry_count", "created_at", "updated_at"]
	end

	private

	def generate_task_uuid
		self.task_uuid ||= SecureRandom.uuid
	end
	def assign_group_id
		self.group_id ||= SecureRandom.uuid
	end

end
