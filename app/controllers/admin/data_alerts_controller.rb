class Admin::DataAlertsController < Admin::BaseController
	# ===== 预警阈值配置 =====
	# 连续0浏览
	ZERO_VIEWS_STREAK = 3     # 最近连续 N 条发文浏览量均为0 触发预警
	ZERO_VIEWS_LOOKBACK = 10  # 连续0浏览检测回溯的最大发文条数（连续数展示上限）
	# 封禁列表
	BANNED_LIST_LIMIT = 50    # 最近封禁列表最多展示条数
	# 浏览量骤降
	VIEWS_DROP_BASELINE = 100 # 前7天单篇平均浏览量需达到的基线
	VIEWS_DROP_RATIO = 0.5    # 近7天均值低于前7天均值的此比例 触发预警
	# 连续发布失败
	FAIL_STREAK = 2           # 最近连续 N 次任务失败 触发预警
	FAIL_LOOKBACK_DAYS = 14   # 连续失败检测回溯天数
	FAIL_LOOKBACK_COUNT = 5   # 连续失败检测回溯的最大日志条数（连续数展示上限）

	def index
		@zero_views_accounts = fetch_zero_views_accounts
		@recent_banned_accounts = fetch_recent_banned_accounts
		@views_drop_accounts = fetch_views_drop_accounts
		@fail_streak_accounts = fetch_fail_streak_accounts
	end

	# 抽屉内容：账号详情（概览 / 发文数据 / 任务日志）
	def account
		@account = Account.find(params[:id])
		@recent_posts = @account.post_stats.order(post_date: :desc).limit(10)
		@recent_logs = TaskLog.where(account_id: @account.id)
			.order(run_at: :desc)
			.limit(10)
		@browser = @account.browser
		render layout: false
	end

	private

	# 数据类预警仅统计仍在运营中的账号，已封禁账号的数据表现无处置意义
	OPERATING_STATUSES = ["正常", "浏览养护"].freeze

	def accounts_by_id(ids)
		Account.where(id: ids).index_by(&:id)
	end

	# ===== 预警一：最近连续3次发文浏览量均为0的账号 =====
	# 按账号取最近 N 条发文（post_date 倒序），从最新一条向后数连续 views_count=0 的条数，
	# 达到 ZERO_VIEWS_STREAK 即预警
	# 注：服务器 MySQL < 8.0 不支持窗口函数（ROW_NUMBER OVER），
	#     改为先筛出发文数达标的运营中账号，再逐账号按 account_id 索引取最近 N 条
	def fetch_zero_views_accounts
		candidate_ids = PostStat.where(account_id: Account.where(status: OPERATING_STATUSES))
			.group(:account_id)
			.having("COUNT(*) >= ?", ZERO_VIEWS_STREAK)
			.pluck(:account_id)

		accounts = accounts_by_id(candidate_ids)

		candidate_ids.filter_map do |account_id|
			posts = PostStat.where(account_id: account_id)
				.order(post_date: :desc, id: :desc)
				.limit(ZERO_VIEWS_LOOKBACK)
				.to_a

			streak = posts.take_while { |post| post.views_count.to_i == 0 }.size
			next nil if streak < ZERO_VIEWS_STREAK

			account = accounts[account_id]
			next nil unless account

			{ account: account, streak: streak, recent_posts: posts.first(ZERO_VIEWS_STREAK) }
		end.sort_by { |item| -item[:streak] }
	end

	# ===== 预警二：最近被封禁的账号 =====
	# accounts 表无专门封禁时间字段，以状态变更时的 updated_at 近似
	def fetch_recent_banned_accounts
		Account.where(status: "封禁/停用")
			.order(updated_at: :desc)
			.limit(BANNED_LIST_LIMIT)
	end

	# ===== 预警三：发文浏览量骤降的账号 =====
	# 对比 近7天 与 前7天 的单篇平均浏览量：
	#   前7天均值 >= VIEWS_DROP_BASELINE 且 近7天有发文 且 降幅 >= 1 - VIEWS_DROP_RATIO 触发预警
	def fetch_views_drop_accounts
		today = Date.today
		recent_range = (today - 6)..today
		prev_range = (today - 13)..(today - 7)
		scope = PostStat.where(account_id: Account.where(status: OPERATING_STATUSES))

		recent_avg = scope.where(post_date: recent_range).group(:account_id).average(:views_count)
		prev_avg = scope.where(post_date: prev_range).group(:account_id).average(:views_count)
		accounts = accounts_by_id(recent_avg.keys)

		recent_avg.filter_map do |account_id, current|
			base = prev_avg[account_id]
			next nil if base.nil? || base < VIEWS_DROP_BASELINE
			next nil if current.nil?

			drop_ratio = 1 - (current / base)
			next nil if drop_ratio < VIEWS_DROP_RATIO

			account = accounts[account_id]
			next nil unless account

			{
				account: account,
				prev_avg: base.round(1),
				recent_avg: current.round(1),
				drop_percent: (drop_ratio * 100).round(1)
			}
		end.sort_by { |item| -item[:drop_percent] }
	end

	# ===== 预警四：最近连续发布失败的账号 =====
	# 回溯近14天任务日志，按账号取最近 N 条（run_at 倒序，MySQL DESC 排序时 NULL 排在末尾），
	# 从最新一条向后数连续 failed 的条数，达到 FAIL_STREAK 即预警
	# 注：同样避开窗口函数，先筛出回溯期内有日志的运营中账号，再逐账号取最近 N 条
	def fetch_fail_streak_accounts
		candidate_ids = TaskLog.where(account_id: Account.where(status: OPERATING_STATUSES))
			.where("run_at >= ?", FAIL_LOOKBACK_DAYS.days.ago)
			.distinct
			.pluck(:account_id)

		accounts = accounts_by_id(candidate_ids)

		candidate_ids.filter_map do |account_id|
			logs = TaskLog.where(account_id: account_id)
				.where("run_at >= ?", FAIL_LOOKBACK_DAYS.days.ago)
				.order(run_at: :desc, id: :desc)
				.limit(FAIL_LOOKBACK_COUNT)
				.to_a

			streak = logs.take_while { |log| log.status == "failed" }.size
			next nil if streak < FAIL_STREAK

			account = accounts[account_id]
			next nil unless account

			last_log = logs.first
			{
				account: account,
				streak: streak,
				last_failed_at: last_log&.run_at,
				last_error: last_log&.error_msg
			}
		end.sort_by { |item| -item[:streak] }
	end
end
