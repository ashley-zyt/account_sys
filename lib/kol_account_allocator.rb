# KOL 内部发信账号调度器
#
# 负责在自动化/人工触达时，为目标平台分配一个可用的内部账号，策略：
#   1. 高曝光优先：读取 post_stats，优先使用近一周发帖浏览量最高的同平台活跃账号
#   2. 安全限流：单个内部账号每日最多联系 5 个 KOL
#   3. 风控休眠：命中风控的账号休眠一段时间，期间不参与分配
class KolAccountAllocator
  MAX_CONTACTS_PER_DAY = 5
  SLEEP_HOURS = 24

  class << self
    # 分配一个可用账号；无可用账号返回 nil
    def allocate(platform, exclude_ids: [])
      ordered_candidates(platform).each do |account|
        next if exclude_ids.include?(account.id)
        next if account.kol_sleeping?
        next if today_contact_count(account) >= MAX_CONTACTS_PER_DAY
        return account
      end
      nil
    end

    # 风控后休眠内部账号
    def sleep_account(account, hours: SLEEP_HOURS)
      account.update!(kol_sleep_until: hours.hours.from_now)
    end

    private

    # 候选账号：高曝光（近7天发帖浏览量）优先，无发帖数据的活跃账号兜底
    def ordered_candidates(platform)
      high_exposure = Account.active.where(platform: platform)
        .joins(:post_stats)
        .where(post_stats: { post_date: 7.days.ago.to_date..Date.today })
        .group("accounts.id")
        .order(Arel.sql("COALESCE(SUM(post_stats.views_count), 0) DESC"))
        .to_a

      high_ids = high_exposure.map(&:id)
      fallback_scope = Account.active.where(platform: platform)
      fallback_scope = fallback_scope.where.not(id: high_ids) if high_ids.present?
      fallback = fallback_scope.order(last_used_at: :asc).to_a

      high_exposure + fallback
    end

    # 单个账号今日已触达的 KOL 数量（按当日发出的 outgoing 消息计数）
    def today_contact_count(account)
      KolMessage.where(account_id: account.id, direction: KolMessage.directions[:outgoing])
        .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
        .count
    end
  end
end
