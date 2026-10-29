# 反推「可能出问题」的账号（机器迁移后排查）
#
# 用法：
#   bundle exec rails runner scripts/detect_stalled_accounts.rb [N]
#   N = 停滞天数阈值（默认 3）
#
# 信号（两个维度，同时停滞才判定为可疑）：
#   1. 采集停滞：max(最新发文时间 post_date, 最后更新发文时间 data_updated_at) 早于 N 天前
#   2. 成功停滞：最后一次成功任务时间（TaskLog status=success 的 MAX(run_at)）早于 N 天前
#   两个都停滞 → 判定「可疑」。任一方面近期还活跃（比如最后成功是今天/昨天）则视为正常。
#
# 只看「正常」状态账号；按「机器 → 浏览器」聚合输出。

STALL_DAYS = 3

def run
  days = (ARGV[0].presence || STALL_DAYS).to_i
  threshold = Time.current - days.days

  puts "=" * 80
  puts "问题账号检测：阈值 #{days} 天（采集与最后成功都早于 #{threshold.strftime('%Y-%m-%d %H:%M')}）"
  puts "=" * 80

  accounts = Account.active.select(:id, :account_name, :platform, :browser_id).to_a
  account_ids = accounts.map(&:id)

  if account_ids.empty?
    puts "无「正常」状态账号。"
    return
  end

  # 1. 采集时间：取「最新发文时间」与「最后更新发文时间」中较新的那个
  collect = {}
  Account.active.joins(:post_stats).group('accounts.id')
          .select("accounts.id, MAX(post_stats.post_date) AS last_post_date, MAX(post_stats.data_updated_at) AS last_data_update")
          .each do |r|
            t1 = r.last_post_date ? Time.zone.local(r.last_post_date.year, r.last_post_date.month, r.last_post_date.day) : nil
            t2 = r.last_data_update
            collect[r.id] = [t1, t2].compact.max
          end

  # 2. 最后一次成功任务时间（不限最近 N 天）
  last_success_at = TaskLog.where(account_id: account_ids, status: TaskLog.statuses[:success])
                           .group(:account_id).maximum(:run_at)

  # 判定：采集停滞 且 成功停滞
  flagged = []
  accounts.each do |a|
    lc = collect[a.id]
    ls = last_success_at[a.id]

    collect_stalled = lc.nil? || lc < threshold
    success_stalled = ls.nil? || ls < threshold
    next unless collect_stalled && success_stalled

    flagged << { account: a, last_collected: lc, last_success_at: ls }
  end

  puts "\n正常账号总数：#{accounts.size}"
  puts "可疑账号总数：#{flagged.size}"

  if flagged.empty?
    puts "未发现可疑账号。"
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
    puts "\n----- 机器：#{machine}（可疑 #{items.size} 个）-----"
    items.each do |f|
      a = f[:account]
      lc = f[:last_collected]
      ls = f[:last_success_at]
      collect_txt = lc ? "#{lc.strftime('%m-%d %H:%M')}(#{(Time.current - lc) / 86400.0} 天前)" : "无记录"
      success_txt = ls ? "#{ls.strftime('%m-%d %H:%M')}(#{(Time.current - ls) / 86400.0} 天前)" : "无成功"
      puts sprintf("  %-24s %-9s 采集:%s 最后成功:%s",
                   a.account_name, a.platform, collect_txt, success_txt)
    end
  end
end

run
