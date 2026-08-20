# KOL 内部发信账号调度器
#
# 分配策略：
#   1. 账号状态=正常 且 平台一致
#   2. 近 7 天有发文，且「每条发文的平均浏览量」> 10
#   3. 按平均浏览量从高到低选择
#   4. 单个账号每日最多联系 5 个 KOL
#   5. 风控/发送失败的账号休眠一段时间，期间不参与分配
class KolAccountAllocator
  MAX_CONTACTS_PER_DAY = 5
  MIN_AVG_VIEWS = 10
  SLEEP_HOURS = 24
  # 当前只接通 twitter；接入其它平台后在此扩展
  SUPPORTED_PLATFORMS = %w[twitter].freeze

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

    # 正常 + 同平台 + 近7天有发文 + 平均浏览量>10，按平均浏览量降序
    def ordered_candidates(platform)
      Account.active.where(platform: platform)
        .joins(:post_stats)
        .where(post_stats: { post_date: 7.days.ago.to_date..Date.today })
        .group("accounts.id")
        .having("SUM(post_stats.views_count) / COUNT(post_stats.id) > ?", MIN_AVG_VIEWS)
        .order(Arel.sql("SUM(post_stats.views_count) / COUNT(post_stats.id) DESC"))
        .to_a
    end

    # 单个账号今日已触达的 KOL 数量（按当日发出的 outgoing 消息计数）
    def today_contact_count(account)
      KolMessage.where(account_id: account.id, direction: KolMessage.directions[:outgoing])
        .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
        .count
    end
  end
end
