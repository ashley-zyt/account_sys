# -*- coding: utf-8 -*-
# 统计各平台：正常状态账号数、今日发文成功数、今日发文失败数
#
# 用法：bundle exec rails runner scripts/publish_daily_summary.rb
#
# 口径：
#   - 正常账号数：Account.status = 0（正常）的账号数，按平台分组
#   - 今日成功/失败：TaskLog（发文日志）run_at 在今天范围内，按 status(success=0/failed=1) 统计，
#     平台由日志的 account_id 快照关联到 accounts.platform

# 平台枚举整数值 → 显示名（与 app/models/account.rb 的 enum platform 一致）
PLATFORMS = {
  1 => "Facebook",
  2 => "X",
  3 => "TikTok",
  4 => "YouTube",
  5 => "Instagram"
}.freeze

# 中文/全角字符按双宽计算，保证表格对齐
def display_width(str)
  str.to_s.each_char.sum { |c| c.bytesize > 1 ? 2 : 1 }
end

def pad(str, width)
  str = str.to_s
  str + (" " * [width - display_width(str), 0].max)
end

# group().count 的 key 可能是整数或字符串（取决于是否为 raw SQL group），统一转整数
def int_key(k)
  return nil if k.nil?
  k.to_i
end

today = Date.today
today_start = today.beginning_of_day
today_end = today.end_of_day

# 1. 各平台正常账号数
normal_counts = {}
Account.where(status: 0).group(:platform).count.each { |p, c| normal_counts[int_key(p)] = c }

# 2. 今日发文日志，按「账号平台 + 状态」统计（LEFT JOIN 保留 account_id 为空的日志，避免漏计）
success_counts = {}
failed_counts = {}
TaskLog.where(run_at: today_start..today_end)
       .joins("LEFT JOIN accounts a ON a.id = task_logs.account_id")
       .group("a.platform", "task_logs.status")
       .count
       .each do |(p, s), c|
  platform = int_key(p)
  if int_key(s) == 1   # failed
    failed_counts[platform] = c
  else                 # success（0）
    success_counts[platform] = c
  end
end

puts "===== 发文统计（#{today.strftime('%Y-%m-%d')}）====="
puts
puts "#{pad('平台', 12)}#{pad('正常账号', 10)}#{pad('今日成功', 10)}#{pad('今日失败', 10)}"

total_normal = 0
total_success = 0
total_failed = 0

PLATFORMS.each do |p, name|
  normal = normal_counts[p] || 0
  s = success_counts[p] || 0
  f = failed_counts[p] || 0
  total_normal += normal
  total_success += s
  total_failed += f
  puts "#{pad(name, 12)}#{pad(normal, 10)}#{pad(s, 10)}#{pad(f, 10)}"
end

# 未知平台（account_id 为 nil 或账号已物理删除的日志）
u_s = success_counts[nil] || 0
u_f = failed_counts[nil] || 0
total_success += u_s
total_failed += u_f
puts "#{pad('未知平台', 12)}#{pad('-', 10)}#{pad(u_s, 10)}#{pad(u_f, 10)}" if u_s.positive? || u_f.positive?

puts
puts "#{pad('合计', 12)}#{pad(total_normal, 10)}#{pad(total_success, 10)}#{pad(total_failed, 10)}"
