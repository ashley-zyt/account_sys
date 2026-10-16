# ===== 发布对账：查某天「正常账号」中未正常发布的账号及原因 =====
#
# 背景：每日日志的成功数 + 失败数 不等于正常账号总量，差额原因可能包括：
#   - agent 外部发布（work_type=agent，发布完全走外部软件，系统无日志）
#   - 资源不足（该主题+平台无 pending 资源可分配）
#   - 未绑定浏览器 / 无 machine_ip（无法发布）
#   - 有资源但当天没发布（调度遗漏/没到窗口等，需人工核查）
#
# 用法：
#   bundle exec rails runner scripts/audit_unpublished_accounts.rb              # 默认今天，全部平台
#   bundle exec rails runner scripts/audit_unpublished_accounts.rb 2026-10-15   # 指定日期
#   bundle exec rails runner scripts/audit_unpublished_accounts.rb 2026-10-15 youtube # 指定平台

date = (ARGV[0].present? ? Date.parse(ARGV[0]) : Date.today)
platform_filter = ARGV[1].presence

day_start = date.beginning_of_day
day_end   = date.end_of_day

# 1. 正常账号
normal = Account.where(status: Account.statuses['正常'])
normal = normal.where(platform: Account.platforms[platform_filter]) if platform_filter.present?

# 2. 当天有发布日志的账号（去重）
logged_ids = TaskLog.where(run_at: day_start..day_end)
                    .where.not(account_id: nil)
                    .distinct.pluck(:account_id)

# 3. 成功/失败账号数（复用 PublishDailySummary 口径：按账号去重取最后一次，排除封禁）
summary      = PublishDailySummary.compute(date, include_failed_accounts: false)
total_success = summary[:total][:success]
total_failed  = summary[:total][:failed]
normal_total  = normal.count

# 4. 差额账号 = 正常 - 有日志
missing = normal.where.not(id: logged_ids).includes(:browser).order(:platform, :id)

# 5. 当天失败后封禁的账号（failed 被 PublishDailySummary 排除，也属「未正常发布」）
banned_failed_ids = TaskLog.where(run_at: day_start..day_end)
                           .where(status: TaskLog.statuses[:failed])
                           .where.not(account_id: nil)
                           .distinct.pluck(:account_id)
banned_failed_count = Account.unscoped.where(id: banned_failed_ids)
                                      .where(status: Account.statuses['封禁/停用']).count

# 分类单个账号的「未发布」原因
def classify_account(a)
  return 'agent外部发布' if a.work_type.to_s == 'agent'
  return '未绑定浏览器/无IP' if a.browser.blank? || a.browser.machine_ip.blank?

  model = a.task_model_for_work_type
  return '无资源队列模式' unless model

  pending = model.where(theme: a.theme, platform: a.platform, status: :pending).count
  pending.zero? ? '资源不足(无pending)' : '有资源未发布(待核查)'
end

categories  = Hash.new(0)
by_platform = Hash.new { |h, k| h[k] = { accounts: 0, cats: Hash.new(0) } }

missing.find_each do |a|
  reason = classify_account(a)
  categories[reason] += 1
  bp = by_platform[a.platform]
  bp[:accounts] += 1
  bp[:cats][reason] += 1
end

# ---- 输出汇总 ----
puts "==== #{date} 发布对账 ===="
puts "正常账号总数:            #{normal_total}"
puts "当天日志成功(去重账号):  #{total_success}"
puts "当天日志失败(去重账号):  #{total_failed}"
puts "差额(正常但无日志):      #{missing.size}"
puts "当天失败后封禁账号:      #{banned_failed_count}"
puts
puts "差额账号原因分布:"
categories.sort_by { |_r, c| -c }.each { |r, c| puts "  #{r}: #{c}" }
puts
puts "按平台差额分布:"
by_platform.sort.each do |platform, info|
  cat_str = info[:cats].sort_by { |_r, c| -c }.map { |r, c| "#{r}=#{c}" }.join(', ')
  puts "  #{platform}: 差额 #{info[:accounts]} 个（#{cat_str}）"
end

# ---- 输出明细 ----
puts
puts "==== 差额账号明细 ===="
missing.find_each do |a|
  reason = classify_account(a)
  puts "  ##{a.id} #{a.account_name} | 平台=#{a.platform} 主题=#{a.theme} 模式=#{a.work_type} | #{reason}"
end
puts
puts "共 #{missing.size} 个差额账号。"
