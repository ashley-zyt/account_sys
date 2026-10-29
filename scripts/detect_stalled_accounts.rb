# 反推「可能出问题」的账号（机器迁移后排查）
#
# 用法：
#   bundle exec rails runner scripts/detect_stalled_accounts.rb [N]
#   N = 停滞天数阈值（默认 3）
#
# 信号（合并两个维度）：
#   1. 采集停滞：post_stats 最后采集时间（COALESCE(MAX(data_updated_at), MAX(created_at))）早于 N 天前
#   2. 任务失败：最近 N 天内存在 status=failed 的 TaskLog
#   任一命中即判定为「可疑账号」，并附上任务日志上下文（失败次数/最近错误/最后任务时间）
#
# 只看「正常」状态账号；按「机器 → 浏览器」聚合输出。

STALL_DAYS = 3

def run
  days = (ARGV[0].presence || STALL_DAYS).to_i
  threshold = Time.current - days.days
  failed_val = TaskLog.statuses[:failed]

  puts "=" * 90
  puts "问题账号检测：阈值 #{days} 天（采集/任务最后时间早于 #{threshold.strftime('%Y-%m-%d %H:%M')}）"
  puts "=" * 90

  accounts = Account.active.select(:id, :account_name, :platform, :browser_id).to_a
  account_ids = accounts.map(&:id)

  if account_ids.empty?
    puts "无「正常」状态账号。"
    return
  end

  # 1. 采集最后时间（有 post_stats 的账号）
  collect = {}
  Account.active.joins(:post_stats).group('accounts.id')
          .select("accounts.id, COALESCE(MAX(post_stats.data_updated_at), MAX(post_stats.created_at)) AS last_collected_at")
          .each { |r| collect[r.id] = r.last_collected_at }

  # 2. 最近 N 天失败任务：失败次数 + 最近错误（按 run_at 倒序，取第一条错误）
  recent_failed_count = {}
  recent_error = {}
  TaskLog.where(account_id: account_ids, status: failed_val)
         .where(run_at: threshold..Time.current)
         .order(run_at: :desc)
         .pluck(:account_id, :error_msg)
         .each do |aid, msg|
           recent_failed_count[aid] = recent_failed_count.fetch(aid, 0) + 1
           recent_error[aid] ||= msg
         end

  # 3. 最后一次成功任务时间（不限最近 N 天）
  last_success_at = TaskLog.where(account_id: account_ids, status: TaskLog.statuses[:success]).group(:account_id).maximum(:run_at)

  # 判定
  flagged = []
  accounts.each do |a|
    lc = collect[a.id]
    fc = recent_failed_count.fetch(a.id, 0)

    collect_stalled = lc.nil? || lc < threshold
    task_failed = fc > 0
    next unless collect_stalled || task_failed

    reasons = []
    reasons << '采集停滞' if collect_stalled
    reasons << '任务失败' if task_failed

    flagged << {
      account: a,
      reason: reasons.join('+'),
      last_collected: lc,
      failed_count: fc,
      last_error: recent_error[a.id],
      last_success_at: last_success_at[a.id],
    }
  end

  collect_stalled_n = flagged.count { |f| f[:reason].include?('采集停滞') }
  task_failed_n = flagged.count { |f| f[:reason].include?('任务失败') }

  puts "\n正常账号总数：#{accounts.size}"
  puts "可疑账号总数：#{flagged.size}（采集停滞 #{collect_stalled_n}，任务失败 #{task_failed_n}，可能重叠）"

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
      days_stalled = lc ? ((Time.current - lc) / 86400.0).round(1) : nil
      collect_txt = lc ? "#{lc.strftime('%m-%d %H:%M')}(#{days_stalled}天前)" : "无记录"
      err = f[:last_error].to_s.strip
      err = err[0, 40] + "..." if err.length > 40
      lta = f[:last_success_at] ? f[:last_success_at].strftime('%m-%d %H:%M') : "无"
      puts sprintf("  %-24s %-9s 原因:%-12s 采集:%s 失败:%d 最近错误:%-42s 最后成功:%s",
                   a.account_name, a.platform, f[:reason], collect_txt, f[:failed_count], err, lta)
    end
  end
end

run
