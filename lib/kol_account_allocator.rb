# KOL 内部发信账号调度器
#
# 分配策略：
#   1. 账号状态=正常 且 平台一致
#   2. 「近七条发文」的平均浏览量 > 10（一条发文都没有则略过）
#   3. 按平均浏览量从高到低选择
#   4. 单个账号每日最多联系 5 个 KOL
#   5. 风控/发送失败的账号休眠一段时间，期间不参与分配
class KolAccountAllocator
  MAX_CONTACTS_PER_DAY = 5
  MIN_AVG_VIEWS = 10
  SLEEP_HOURS = 24
  # 当前已接通 twitter / tiktok；接入其它平台后在此扩展
  SUPPORTED_PLATFORMS = %w[twitter tiktok].freeze

  class << self
    def supported_platform?(platform)
      SUPPORTED_PLATFORMS.include?(platform.to_s)
    end

    # 分配一个可用账号；无可用账号或平台未接通时返回 nil
    def allocate(platform, exclude_ids: [])
      return nil unless supported_platform?(platform)

      ordered_candidates(platform).each do |account|
        next if exclude_ids.include?(account.id)
        next if account.kol_sleeping?
        next if today_contact_count(account) >= MAX_CONTACTS_PER_DAY
        return account
      end
      nil
    end

    # 发送失败/风控后休眠内部账号
    def sleep_account(account, hours: SLEEP_HOURS)
      account.update!(kol_sleep_until: hours.hours.from_now)
    end

    private

    # 正常 + 同平台，按「近七条发文」的平均浏览量降序；
    # 一条发文都没有的账号直接略过（不参与分配）。
    def ordered_candidates(platform)
      account_ids = Account.active.where(platform: platform).pluck(:id)
      return [] if account_ids.empty?

      # 按发文日期倒序拉取每个账号的浏览量，再逐个账号截取最近 7 条
      stats = PostStat.where(account_id: account_ids)
                      .order(account_id: :asc, post_date: :desc, id: :desc)
                      .pluck(:account_id, :views_count)

      by_account = Hash.new { |h, k| h[k] = [] }
      stats.each do |account_id, views_count|
        list = by_account[account_id]
        list << views_count.to_i if list.size < 7
      end

      scored = []
      by_account.each do |account_id, views|
        next if views.empty?          # 一条发文都没有：略过
        avg = views.sum.to_f / views.size
        next if avg <= MIN_AVG_VIEWS  # 平均浏览量不达标：略过
        scored << [account_id, avg]
      end

      scored.sort_by! { |_id, avg| -avg }
      ids = scored.map(&:first)
      accounts_by_id = Account.where(id: ids).index_by(&:id)
      ids.map { |id| accounts_by_id[id] }.compact
    end

    # 单个账号今日已触达的 KOL 数量（仅按当日「发送成功」的消息计数，失败尝试不占配额）
    def today_contact_count(account)
      KolMessage.where(
        account_id: account.id,
        direction: KolMessage.directions[:outgoing],
        status: KolMessage.statuses[:sent_success]
      ).where(created_at: Time.current.beginning_of_day..Time.current.end_of_day).count
    end
  end
end
