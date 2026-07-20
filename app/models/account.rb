# == Schema Information
#
# Table name: accounts
#
#  id                                                        :bigint           not null, primary key
#  account_name(账号名)                                      :string(255)
#  last_used_at(最后一次使用时间)                            :datetime
#  operator                                                  :string(255)
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
	has_many :operation_tasks, dependent: :nullify
	has_many :grok_tasks, dependent: :nullify
	has_many :heygen_tasks, dependent: :nullify
	has_many :warmup_tasks, dependent: :nullify
	has_one :warmup_profile, dependent: :destroy
	# 通过 task_logs.account_id 快照反查该账号的所有执行日志（兼容运营任务被释放资源的场景）
	has_many :task_logs, foreign_key: :account_id, dependent: :nullify
	# 账号可参与多个会话
	has_many :conversations, dependent: :destroy
	# 账号可有多条发文数据记录
	has_many :post_stats, dependent: :destroy

	# 回调：当账号状态变更时，同步更新浏览器的“无效”状态
	after_save :sync_browser_status, if: :saved_change_to_status?
	after_save :sync_warmup_enabled, if: :saved_change_to_status?
	after_create :create_warmup_profile

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
		instagram: 5
	}

	# 账号状态枚举
	# - normal    : 正常启用，可参与任务分配
	# - restricted: 受限（如风控、临时限制），调度时应跳过
	# - banned    : 封禁/停用，不再使用
	enum status: {
		"正常": 0,
		"未登录": 1,
		"封禁/停用": 2,
		"浏览养护": 3,
	}

	# 工作模式枚举（预留扩展）
	# - move  : 视频搬运（当前主要用途）
	# - coze  : 调用 coze 等 AI 生成内容
	# - other : 其他自定义模式
	enum work_type: {
		"视频搬运": 0,
		"coze": 1,
		"剪映": 2,
		"人工运营": 3,
		"Grok": 4,
		"Heygen": 5
	}

	# 运营人员枚举
	OPERATORS = ["张俊", "许淑雯", "石欢欢", "杜维"]

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

	# 根据工作模式返回对应的任务模型类
	def task_model_for_work_type
		case work_type
		when "视频搬运"
			MoveTask
		when "剪映"
			JianyingTask
		when "人工运营"
			OperationTask
		when "Grok"
			GrokTask
		when "Heygen"
			HeygenTask
		end
	end

	# 获取最后一次运行的日志
	# 优先使用 task_logs.account_id 快照查询（兼容运营任务被释放资源的场景），
	# 若快照缺失，再回退到通过关联任务查找
	def last_task_log
		@last_task_log ||= compute_last_task_log
	end

	# 获取最后使用时间（从任务日志表获取）
	def last_used_at
		last_task_log&.run_at || super
	end

	# 获取该账号最后一次成功运行任务的时间
	def last_successful_run_at
		move_uuids = move_tasks.select(:task_uuid)
		jianying_uuids = jianying_tasks.select(:task_uuid)
		grok_uuids = grok_tasks.select(:task_uuid)
		heygen_uuids = heygen_tasks.select(:task_uuid)
		
		TaskLog.success
		       .where("task_uuid IN (?) OR task_uuid IN (?) OR task_uuid IN (?) OR task_uuid IN (?)", move_uuids, jianying_uuids, grok_uuids, heygen_uuids)
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

	def warmup_due?
		warmup_profile&.warmup_due? || false
	end

	private

	# 同步更新浏览器的状态
	def sync_browser_status
		browser&.update_status_by_accounts!
	end

	# 创建养号配置
	def create_warmup_profile
		WarmupProfile.create!(
			account: self,
			machine: work_type == '视频搬运' ? 'move' : 'other'
		)
	end

	# 同步养号启用状态：
	# - 正常(0) 或 浏览养护(3) → warmup_enabled = true
	# - 未登录(1) 或 封禁/停用(2) → warmup_enabled = false
	def sync_warmup_enabled
		profile = warmup_profile
		return unless profile

		case status
		when "正常", "浏览养护"
			profile.update!(warmup_enabled: true) if !profile.warmup_enabled
		when "封禁/停用", "未登录"
			profile.update!(warmup_enabled: false) if profile.warmup_enabled
		end
	end

	# 计算最后一次运行的日志（被 last_task_log 委托）
	def compute_last_task_log
		log = TaskLog.where(account_id: id).order(run_at: :desc).first
		return log if log

		task_model = task_model_for_work_type
		return nil unless task_model

		uuids = task_model.where(account_id: id).pluck(:task_uuid).compact
		return nil if uuids.empty?
		TaskLog.where(task_uuid: uuids).order(run_at: :desc).first
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
		["browser", "move_tasks", "warmup_profile"]
	end

	# Ransack 搜索允许的字段
	def self.ransackable_attributes(auth_object = nil)
		["id", "account_name", "theme", "platform", "status", "work_type", "browser_id", "last_used_at", "remark", "operator", "created_at", "updated_at"]
	end
end
