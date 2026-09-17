# -*- coding: utf-8 -*-
# 诊断：正常状态账号中「当天有发文」vs「当天无发文」的差异，排查「日志成功数+失败数 ≠ 账号总数」的原因
#
# 用法：
#   bundle exec rails runner scripts/diagnose_post_gap.rb tiktok
#   bundle exec rails runner scripts/diagnose_post_gap.rb youtube
#   bundle exec rails runner scripts/diagnose_post_gap.rb   # 不传平台则查所有平台

platform = ARGV[0].to_s.strip.downcase

today_start = Date.today.beginning_of_day
today_end = Date.today.end_of_day

scope = Account.where(status: 0)
scope = scope.where(platform: platform) if platform.present? && Account.platforms.key?(platform)

accounts = scope.to_a
total = accounts.size

# 当天有发文日志（TaskLog）的账号 id
posted_ids = TaskLog.where(run_at: today_start..today_end)
                    .where.not(account_id: nil)
                    .distinct.pluck(:account_id)

posted = accounts.select { |a| posted_ids.include?(a.id) }
not_posted = accounts.reject { |a| posted_ids.include?(a.id) }

puts "===== 发文缺口诊断（平台=#{platform.presence || '全部'}，日期=#{Date.today}）====="
puts "正常账号总数: #{total}"
puts "当天有发文日志: #{posted.size}"
puts "当天无发文日志: #{not_posted.size}   ← 这就是「账号数 - (成功+失败)」的差额来源"

puts
puts "===== 按工作模式分组（有发文 / 无发文）====="
accounts.group_by(&:work_type).sort.each do |wt, list|
  p = list.count { |a| posted_ids.include?(a.id) }
  n = list.size - p
  puts format("%-14s 共%-5d 发文%-5d 未发%-5d", wt, list.size, p, n)
end

puts
puts "===== 当天无发文的账号明细（#{not_posted.size} 个）====="
not_posted.sort_by(&:id).each do |a|
  last = a.last_task_log
  last_at = last&.run_at&.strftime('%m-%d %H:%M') || '从未'
  zero = (a.respond_to?(:zero_views_in_past_3_days?) && a.zero_views_in_past_3_days?) ? ' [3天0浏览暂停]' : ''
  browser = a.browser&.profile_name || '无'
  puts format("#%-6d %-20s 模式=%-10s 平台=%-9s 主题=%s", a.id, a.account_name, a.work_type, a.platform, a.theme)
  puts format("      最后发文=%s 浏览器=%s%s", last_at, browser, zero)
end

puts
puts "提示：若「未发」账号的工作模式是 agent/coze/人工运营 等不参与自动调度的模式，或带「3天0浏览暂停」标记，即为正常现象（它们本就不走每日自动发布）。"
