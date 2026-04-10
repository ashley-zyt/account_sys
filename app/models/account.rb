# == Schema Information
#
# Table name: accounts
#
#  id                                                        :bigint           not null, primary key
#  account_name(账号名)                                      :string(255)
#  last_used_at(最后一次使用时间)                            :datetime
#  platform(平台：facebook/twitter/tiktok/youtube/instagram) :integer          default("facebook")
#  remark(备注信息)                                          :string(255)
#  source_url(账号主页链接)                                  :string(255)
#  status(账号状态)                                          :integer          default("正常")
#  theme(账号主题)                                           :string(255)
#  work_type(工作运行方式：搬运/coze/其他)                   :integer
#  created_at                                                :datetime         not null
#  updated_at                                                :datetime         not null
#  browser_id(绑定的指纹浏览器ID)                            :bigint
#
# Indexes
#
#  idx_accounts_theme_status_lastused  (theme,status,last_used_at)
#  index_accounts_on_browser_id        (browser_id)
#  index_accounts_on_last_used_at      (last_used_at)
#  index_accounts_on_platform          (platform)
#  index_accounts_on_source_url        (source_url)
#
class Account < ApplicationRecord
	# 每个账号可以绑定一个指纹浏览器（用于发布/养号）
	belongs_to :browser, optional: true
	# 一个账号可产生多个发布任务，账号删除时任务保留（置空 account_id）
	has_many :move_tasks, dependent: :nullify
	has_many :jianying_tasks, dependent: :nullify

	# 回调：当账号状态变更时，同步更新浏览器的“无效”状态
	after_save :sync_browser_status, if: :saved_change_to_status?

	# 基础校验
	validates :account_name, presence: true
	# 主题校验
	validates :theme, presence: true   # 账号必须归属某个主题
	# 平台类型
	enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		# instagram: 5
	}

	# 账号状态枚举
	# - normal    : 正常启用，可参与任务分配
	# - restricted: 受限（如风控、临时限制），调度时应跳过
	# - banned    : 封禁/停用，不再使用
	enum status: {
		"正常": 0,
		"未登录": 1,
		"封禁/停用": 2
	}

	# 工作模式枚举（预留扩展）
	# - move  : 视频搬运（当前主要用途）
	# - coze  : 调用 coze 等 AI 生成内容
	# - other : 其他自定义模式
	enum work_type: {
		"视频搬运": 0,
		"coze": 1,
		"capcut": 2
	}

	# 作用域：获取当前可用的账号（仅 正常 状态）
	scope :active, -> {
		正常
	}

	# 作用域：获取指定主题下可用的账号，按最久未使用排序（公平轮询）
	# 使用示例：Account.available_for_theme('美食教程')
	scope :available_for_theme, ->(theme) {
		active.where(theme: theme)
			.order('last_used_at ASC NULLS FIRST')
	}

	# 获取指定主题、指定平台下可用的最久未使用账号
	scope :available_for_theme_and_platform, ->(theme, platform) {
		active.where(theme: theme, platform: platform).order(last_used_at: :asc)
	}

	# 实例方法：标记账号已被使用，更新 last_used_at
	# 每次分配任务后必须调用此方法，以保证公平轮询
	def mark_as_assigned!
		update!(last_used_at: Time.current)
	end

	# 获取最后一次运行的日志
	def last_task_log
		@last_task_log ||= TaskLog.where(task_uuid: move_tasks.select(:task_uuid)).order(run_at: :desc).first
	end

	# 获取该账号最后一次成功运行任务的时间
	def last_successful_run_at
		# 结合搬运任务和剪映任务的成功日志进行查询
		move_uuids = move_tasks.select(:task_uuid)
		jianying_uuids = jianying_tasks.select(:task_uuid)
		
		TaskLog.success
		       .where("task_uuid IN (?) OR task_uuid IN (?)", move_uuids, jianying_uuids)
		       .order(run_at: :desc)
		       .pick(:run_at)
	end

	# 类方法：统计所有已封禁或退出的账号及其最后一次成功运行时间
	def self.banned_or_unlogged_last_success_stats
		# status 1: 未登录, 2: 封禁/停用
		where(status: [ "封禁/停用"]).where(platform:4).find_each.map do |account|
			{
				account_id: account.id,
				account_name: account.account_name,
				platform: account.platform,
				status: account.status,
				last_success_at: account.last_successful_run_at
			}
		end
	end

	private

	# 同步更新浏览器的状态
	def sync_browser_status
		browser&.update_status_by_accounts!
	end

	# --- Ransack 搜索白名单 ---
	def self.ransackable_attributes(auth_object = nil)
		%w[
			id
			account_name
			browser_id
			platform
			status
			theme
			work_type
			last_used_at
			remark
			created_at
			updated_at
		]
	end
	def self.ransackable_associations(auth_object = nil)
		["browser", "move_tasks"]
	end

	# Ransack 搜索允许的字段
	def self.ransackable_attributes(auth_object = nil)
		["id", "account_name", "theme", "platform", "status", "work_type", "browser_id", "last_used_at", "remark", "created_at", "updated_at"]
	end
end
