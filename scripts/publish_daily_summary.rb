# -*- coding: utf-8 -*-
# 统计各平台：正常状态账号数、今日发文最终成功数、最终失败数
#
# 用法：bundle exec rails runner scripts/publish_daily_summary.rb
#
# 口径（参考账号列表页「最后一次是否成功」）：
#   - 正常账号数：Account.status = 0（正常）的账号数，按平台分组
#   - 今日成功/失败：按「账号」去重，取每个账号今日最后一次发文日志（run_at 最大的那条）
#     的 status 作为该账号今日的最终结果。失败重试后成功的，以最后一次为准。
#   - 平台归属：优先用日志的 account_id 快照关联 accounts.platform；
#     若账号已物理删除，则回退用 task_uuid 关联任务表(MoveTask等)的 platform。

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

# 2. 今日发文日志，按账号取「最后一次」执行结果
rows = TaskLog.where(run_at: today_start..today_end)
              .pluck(:account_id, :status, :run_at, :task_uuid)

# 按账号取今日最后一次日志（run_at 最大）
last_by_account = {}
rows.each do |account_id, status, run_at, task_uuid|
  next if account_id.nil?
  cur = last_by_account[account_id]
  if cur.nil? || (run_at && (!cur[:run_at] || run_at > cur[:run_at]))
    last_by_account[account_id] = { status: status, run_at: run_at, task_uuid: task_uuid }
  end
end

# 3. 账号 id → 平台名称：先走 accounts 表（unscoped 含软删除）
account_ids = last_by_account.keys
platform_by_account = {}
Account.unscoped.where(id: account_ids).pluck(:id, :platform).each do |id, p|
  platform_by_account[id] = PLATFORM_BY_INT[p]
end

# 4. 回退：账号已物理删除的，用 task_uuid 关联任务表拿 platform
missing_uuids = last_by_account
                .select { |id, _e| platform_by_account[id].nil? }
                .map { |_id, e| e[:task_uuid] }
                .compact.uniq

task_platform_by_uuid = {}
unless missing_uuids.empty?
  WorkMode.resource_modes.each do |mode|
    mode.task_model_class.where(task_uuid: missing_uuids).pluck(:task_uuid, :platform).each do |uuid, p|
      task_platform_by_uuid[uuid] = PLATFORM_BY_INT[p] if p.present?
    end
  end
end

last_by_account.each do |id, e|
  platform_by_account[id] = task_platform_by_uuid[e[:task_uuid]] if platform_by_account[id].nil?
end

# 5. 按平台统计成功/失败
success_counts = Hash.new(0)
failed_counts = Hash.new(0)
last_by_account.each do |account_id, e|
  platform = platform_by_account[account_id]
  if e[:status] == 0   # success
    success_counts[platform] += 1
  else                 # failed
    failed_counts[platform] += 1
  end
end

puts "===== 发文统计（#{today.strftime('%Y-%m-%d')}）====="
puts "（成功/失败按账号去重，取今日最后一次执行结果）"
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

# 未知平台（账号和任务都查不到平台）
u_s = success_counts[nil] || 0
u_f = failed_counts[nil] || 0
total_success += u_s
total_failed += u_f
puts "#{pad('未知平台', 12)}#{pad('-', 10)}#{pad(u_s, 10)}#{pad(u_f, 10)}" if u_s.positive? || u_f.positive?

puts
puts "#{pad('合计', 12)}#{pad(total_normal, 10)}#{pad(total_success, 10)}#{pad(total_failed, 10)}"

# 调试：定位「未知平台」的来源
puts
puts "--- 调试 ---"
puts "今日日志总数: #{rows.size}"
puts "有发文日志的账号数(去重): #{last_by_account.size}"
puts "仍查不到平台的账号数: #{last_by_account.count { |id, _e| platform_by_account[id].nil? }}"
