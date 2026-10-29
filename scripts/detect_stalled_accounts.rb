# 反推「采集异常」的账号（机器迁移后排查）
#
# 用法：
#   bundle exec rails runner scripts/detect_stalled_accounts.rb [N]
#   N = 停滞天数阈值（默认 2，即今日+昨日）
#
# 核心信号（判定依据）：采集停滞 —— post_stats.data_updated_at 超过阈值没更新。
# 辅助信号（判断原因）：
#   - 最新发文时间 post_date
#   - 最后发布成功时间（TaskLog publish_channel 非空 且 status=success）
#
# 判定：正常账号，data_updated_at 早于阈值（或从没采集）→ 采集异常。
#   - 采集停滞但发文/发布仍活跃 → 「采集异常(发布仍活跃)」，重点查采集端/机器
#   - 采集停滞且发文/发布也停 → 「整体停滞」
#
# 只看「正常」状态账号；按「机器 → 浏览器」聚合输出。

STALL_DAYS = 2

def run
  days = (ARGV[0].presence || STALL_DAYS).to_i
  threshold = Time.current - days.days

  puts "=" * 90
  puts "采集异常检测：阈值 #{days} 天（data_updated_at 早于 #{threshold.strftime('%Y-%m-%d %H:%M')}）"
  puts "=" * 90

  accounts = Account.active.select(:id, :account_name, :platform, :browser_id).to_a
  account_ids = accounts.map(&:id)

  if account_ids.empty?
    puts "无「正常」状态账号。"
    return
  end

  # 1. 采集最后更新 + 最新发文
  collect = {}
  Account.active.joins(:post_stats).group('accounts.id')
          .select("accounts.id, MAX(post_stats.data_updated_at) AS last_collected_at, MAX(post_stats.post_date) AS last_post_date")
          .each { |r| collect[r.id] = r }

  # 2. 最后发布成功时间（发布日志：publish_channel 非空）
  last_publish_success = TaskLog.where(account_id: account_ids)
                                .where.not(publish_channel: nil)
                                .where(status: TaskLog.statuses[:success])
                                .group(:account_id).maximum(:run_at)

  # 判定：采集停滞
  flagged = []
  accounts.each do |a|
    c = collect[a.id]
    lc = c&.last_collected_at

    collect_stalled = lc.nil? || lc < threshold
    next unless collect_stalled

    lpd = c&.last_post_date
    lps = last_publish_success[a.id]

    publish_active =
      (lpd && lpd >= (Date.today - days.days)) ||
      (lps && lps >= threshold)

    flagged << {
      account: a,
      reason: publish_active ? '采集异常(发布仍活跃)' : '整体停滞',
      last_collected_at: lc,
      last_post_date: lpd,
      last_publish_success_at: lps,
    }
  end

  active_n = flagged.count { |f| f[:reason].include?('发布仍活跃') }
  silent_n = flagged.size - active_n

  puts "\n正常账号总数：#{accounts.size}"
  puts "采集异常账号：#{flagged.size}（发布仍活跃 #{active_n}，整体停滞 #{silent_n}）"

  if flagged.empty?
    puts "未发现异常账号。"
    return
  end

  # 浏览器 + 机器
  browser_ids = flagged.map { |f| f[:account].browser_id }.compact.uniq
  browsers = Browser.where(id: browser_ids).includes(:machine).index_by(&:id)

  # 按机器分组
  groups = Hash.new { |h, k| h[k] = [] }
  flagged.each do |f|
    b = browsers[f[:account].browser_id]
    m = b&.machine
    key = m ? "#{m.name}(#{m.host})" : (b ? "无机器(浏览器:#{b.profile_name})" : "无浏览器")
    groups[key] << f.merge(browser: b)
  end

  groups.sort.each do |machine, items|
    puts "\n----- 机器：#{machine}（异常 #{items.size} 个）-----"
    items.each do |f|
      a = f[:account]
      lc = f[:last_collected_at]
      lpd = f[:last_post_date]
      lps = f[:last_publish_success_at]

      collect_txt = lc ? "#{lc.strftime('%m-%d %H:%M')}(#{(Time.current - lc) / 86400.0} 天前)" : "无采集"
      post_txt = lpd ? lpd.strftime('%m-%d') : "无发文"
      publish_txt = lps ? lps.strftime('%m-%d %H:%M') : "无"

      puts sprintf("  %-24s %-9s %-20s 采集:%s 发文:%s 发布成功:%s",
                   a.account_name, a.platform, f[:reason], collect_txt, post_txt, publish_txt)
    end
  end
end

run
