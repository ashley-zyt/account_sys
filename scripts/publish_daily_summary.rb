# -*- coding: utf-8 -*-
# 统计各平台：正常状态账号数、今日发文最终成功数、最终失败数
#
# 用法：bundle exec rails runner scripts/publish_daily_summary.rb
#
# 口径（重要）：
#   - 正常账号数：Account.status = 0（正常）的账号数，按平台分组
#   - 今日最终成功/失败：按「任务(task_uuid)」去重统计最终结果。
#     一个任务可能因失败重试产生多条日志（第一次 failed、第二次 success），
#     这里「最终成功」= 今日至少成功过一次的任务；「最终失败」= 今日只有失败记录、
#     从未成功的任务。避免「失败后重试成功」被重复计入。

# 平台显示名（key 用 Account.platforms 的 enum 名称：facebook/twitter/...）
PLATFORM_NAMES = {
  "facebook"  => "Facebook",
  "twitter"   => "X",
  "tiktok"    => "TikTok",
  "youtube"   => "YouTube",
  "instagram" => "Instagram"
}.freeze

# 平台整数值 → enum 名称（Account.platforms 是 名称→整数，反转为 整数→名称）
PLATFORM_BY_INT = Account.platforms.invert.freeze

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

# 1. 各平台正常账号数（group(:platform) 对 enum 列返回 enum 名称 key）
normal_counts = Account.where(status: 0).group(:platform).count

# 2. 今日发文日志，按任务(task_uuid)去重统计最终成功/失败
logs = TaskLog.where(run_at: today_start..today_end)
              .select(:task_uuid, :status, :account_id)
              .to_a

# 账号 id → 平台 enum 名称（unscoped 绕过软删除，保证已删账号的日志也能归到平台）
account_ids = logs.map(&:account_id).compact.uniq
account_platform = {}
Account.unscoped.where(id: account_ids).pluck(:id, :platform).each do |id, p|
  account_platform[id] = PLATFORM_BY_INT[p]
end

# 按 task_uuid 聚合：只要今日出现过 success 就算最终成功；平台以成功那次账号为准
final = {}
logs.each do |log|
  entry = final[log.task_uuid] ||= { success: false, account_id: nil }
  if log[:status] == 0   # success
    entry[:success] = true
    entry[:account_id] = log.account_id if log.account_id.present?
  else                   # failed
    entry[:account_id] = log.account_id if entry[:account_id].nil? && log.account_id.present?
  end
end

success_counts = Hash.new(0)
failed_counts = Hash.new(0)
final.each_value do |e|
  platform = account_platform[e[:account_id]]
  if e[:success]
    success_counts[platform] += 1
  else
    failed_counts[platform] += 1
  end
end

puts "===== 发文统计（#{today.strftime('%Y-%m-%d')}）====="
puts "（成功/失败按任务去重：失败后重试成功的任务只计成功一次）"
puts
puts "#{pad('平台', 12)}#{pad('正常账号', 10)}#{pad('最终成功', 10)}#{pad('最终失败', 10)}"

total_normal = 0
total_success = 0
total_failed = 0

PLATFORM_NAMES.each do |key, name|
  normal = normal_counts[key] || 0
  s = success_counts[key] || 0
  f = failed_counts[key] || 0
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
