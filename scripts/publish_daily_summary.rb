# -*- coding: utf-8 -*-
# 统计各平台：正常状态账号数、今日发文成功数、今日发文失败数
#
# 用法：bundle exec rails runner scripts/publish_daily_summary.rb
#
# 口径：
#   - 正常账号数：Account.status = 正常 的账号数（按平台分组）
#   - 今日成功/失败：TaskLog（发文日志）run_at 在今天范围内，
#     按 status(success/failed) 统计，平台由日志的 account_id 快照关联到 accounts.platform

PLATFORM_NAMES = {
  "facebook"  => "Facebook",
  "twitter"   => "X",
  "tiktok"    => "TikTok",
  "youtube"   => "YouTube",
  "instagram" => "Instagram"
}.freeze

# 中文/全角字符按双宽计算，保证表格对齐
def display_width(str)
  str.to_s.each_char.sum { |c| c.bytesize > 1 ? 2 : 1 }
end

def pad(str, width)
  str = str.to_s
  str + (" " * [width - display_width(str), 0].max)
end

today = Date.today
today_start = today.beginning_of_day
today_end = today.end_of_day

# 1. 各平台正常账号数
normal_counts = Account.where(status: Account.statuses['正常']).group(:platform).count

# 2. 今日发文日志，按「账号平台 + 状态」统计（LEFT JOIN 保留 account_id 为空的日志，避免漏计）
log_counts = TaskLog.where(run_at: today_start..today_end)
                    .joins("LEFT JOIN accounts a ON a.id = task_logs.account_id")
                    .group("a.platform", "task_logs.status")
                    .count

succ = TaskLog.statuses['success']
fail = TaskLog.statuses['failed']

puts "===== 发文统计（#{today.strftime('%Y-%m-%d')}）====="
puts
puts "#{pad('平台', 12)}#{pad('正常账号', 10)}#{pad('今日成功', 10)}#{pad('今日失败', 10)}"

total_normal = 0
total_success = 0
total_failed = 0

Account.platforms.each do |name, p|
  normal = normal_counts[p] || 0
  s = log_counts[[p, succ]] || 0
  f = log_counts[[p, fail]] || 0
  total_normal += normal
  total_success += s
  total_failed += f
  puts "#{pad(PLATFORM_NAMES[name], 12)}#{pad(normal, 10)}#{pad(s, 10)}#{pad(f, 10)}"
end

# 未知平台（account_id 为 nil 或账号已物理删除的日志）
u_s = log_counts[[nil, succ]] || 0
u_f = log_counts[[nil, fail]] || 0
total_success += u_s
total_failed += u_f
puts "#{pad('未知平台', 12)}#{pad('-', 10)}#{pad(u_s, 10)}#{pad(u_f, 10)}" if u_s.positive? || u_f.positive?

puts
puts "#{pad('合计', 12)}#{pad(total_normal, 10)}#{pad(total_success, 10)}#{pad(total_failed, 10)}"
