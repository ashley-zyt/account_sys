# 反推「可能出问题」的账号（机器迁移后排查）
#
# 用法：
#   bundle exec rails runner scripts/detect_stalled_accounts.rb [N]
#   N = 发布成功「活跃」阈值天数（默认 2，即今日+昨日）
#
# 范围：仅「正常」状态账号（剔除封禁/未登录/停用等）。
# 信号（与仪表盘「今日数据更新中」提示同口径）：
#   - 发文数据未更新：post_stats 最新 data_updated_at 不是今天
#   - 账号数据未更新：account_stat 最新 stat_date 不是今天
#   任一命中即判定「今日未更新」→ 可疑。
# 附：最后采集时间、最新发文、最后发布成功时间（判断是采集坏还是整体停摆）。

require 'set'

STALL_DAYS = 2

def run
  days = (ARGV[0].presence || STALL_DAYS).to_i
  threshold = Time.current - days.days

  puts "=" * 90
  puts "问题账号检测（正常账号 · 今日数据未更新）"
  puts "=" * 90

  accounts = Account.active.select(:id, :account_name, :platform, :browser_id, :status).to_a
  account_ids = accounts.map(&:id)

  if account_ids.empty?
    puts "无「正常」状态账号。"
    return
  end

  # 今日未更新（与仪表盘提示同口径：正常 + 非Facebook + 有成功task_log）
  stale = Util.get_stale_accounts(account_ids: account_ids)
  post_stale = stale[:post_stats_stale].to_set
  stat_stale = stale[:stat_stale].to_set

  # 最后采集时间 + 最新发文
  collect = {}
  PostStat.where(account_id: account_ids).group(:account_id)
          .select("account_id, MAX(data_updated_at) AS last_collected_at, MAX(post_date) AS last_post_date")
          .each { |r| collect[r.account_id] = r }

  # 最后发布成功时间（发布日志：publish_channel 非空）
  last_publish_success = TaskLog.where(account_id: account_ids)
                                .where.not(publish_channel: nil)
                                .where(status: TaskLog.statuses[:success])
                                .group(:account_id).maximum(:run_at)

  # 判定：今日发文数据 或 账号数据 未更新
  flagged = accounts.select { |a| post_stale.include?(a.id) || stat_stale.include?(a.id) }

  puts "\n正常账号总数：#{accounts.size}"
  puts "今日数据未更新账号：#{flagged.size}"

  if flagged.empty?
    puts "未发现异常账号。"
    return
  end

  # 浏览器 + 机器
  browser_ids = flagged.map(&:browser_id).compact.uniq
  browsers = Browser.where(id: browser_ids).includes(:machine).index_by(&:id)

  groups = Hash.new { |h, k| h[k] = [] }
  flagged.each do |a|
    b = browsers[a.browser_id]
    m = b&.machine
    key = m ? "#{m.name}(#{m.host})" : (b ? "无机器(浏览器:#{b.profile_name})" : "无浏览器")
    groups[key] << { account: a, browser: b }
  end

  groups.sort.each do |machine, items|
    puts "\n----- 机器：#{machine}（未更新 #{items.size} 个）-----"
    items.each do |it|
      a = it[:account]
      c = collect[a.id]
      lc  = c&.last_collected_at
      lpd = c&.last_post_date
      lps = last_publish_success[a.id]

      types = []
      types << '发文' if post_stale.include?(a.id)
      types << '账号数据' if stat_stale.include?(a.id)
      type_txt = types.join('+')

      collect_txt = lc ? "#{lc.strftime('%m-%d %H:%M')}(#{(Time.current - lc) / 86400.0} 天前)" : "无采集"
      post_txt = lpd ? lpd.strftime('%m-%d') : "无发文"
      publish_txt = lps ? lps.strftime('%m-%d %H:%M') : "无"

      active = (lpd && lpd >= (Date.today - days.days)) || (lps && lps >= threshold)
      reason = active ? '发布仍活跃' : '整体停滞'

      puts sprintf("  %-22s %-8s %-16s %-12s %-10s 采集:%s 发文:%s 发布成功:%s",
                   a.account_name, a.platform, it[:browser]&.profile_name, type_txt, reason,
                   collect_txt, post_txt, publish_txt)
    end
  end
end

run
