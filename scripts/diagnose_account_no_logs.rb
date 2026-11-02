# ===== 诊断账号为什么近几天没有发布日志 =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/diagnose_account_no_logs.rb <account_id>
#
# 沿「资源分配 → 发布 → 日志」逐段排查：账号状态、资源队列、活跃任务、
# 待分配资源、今天是否已发、TikTok 冷却、最近日志。

account_id = ARGV[0]
account = Account.find_by(id: account_id)
abort "账号不存在: #{account_id}" unless account

puts "===== 账号发布诊断 ====="
puts "账号: #{account.account_name} (##{account.id})"
puts "状态: #{account.status}"
puts "工作模式: #{account.work_type}"
puts "主题: #{account.theme}"
puts "平台: #{account.platform}"
puts "浏览器: #{account.browser&.profile_name || '无'}"
puts

task_model = account.task_model_for_work_type
puts "资源队列模型: #{task_model&.name || '无'}"
puts

if task_model.nil?
  puts "❌ 账号 work_type=#{account.work_type} 无对应资源队列，无法分配资源（可能 work_type 与注册表不匹配）"
else
  # 1. 活跃任务
  active_tasks = task_model.where(account_id: account.id, status: [:waiting_publish, :executing])
  puts "[1] 活跃任务（waiting_publish/executing）: #{active_tasks.count} 条"
  active_tasks.order(id: :desc).limit(5).each do |t|
    puts "    ##{t.id} status=#{t.status} platform=#{t.platform} start_at=#{t.start_at&.strftime('%m-%d %H:%M')}"
  end
  puts

  # 2. 该主题+平台的 pending 资源
  pending = task_model.where(status: :pending, theme: account.theme, platform: account.platform)
  puts "[2] 该主题+平台的 pending 资源: #{pending.count} 条"
  puts

  # 3. 今天是否已发布成功
  today_range = Date.today.beginning_of_day..Date.today.end_of_day
  posted_today = task_model.exists?(account_id: account.id, status: :success, actual_publish_time: today_range)
  puts "[3] 今天已发布成功: #{posted_today}"
  puts

  # 4. TikTok 冷却
  if account.platform.to_s == 'tiktok'
    zero = account.zero_views_in_past_3_days?
    puts "[4] TikTok 近3天0浏览冷却: #{zero}"
    puts
  end
end

# 5. 最近日志（与资源模型无关，统一查）
puts "[5] 最近 TaskLog（5 条）"
logs = TaskLog.where(account_id: account.id).order(id: :desc).limit(5)
if logs.empty?
  puts "    无日志"
else
  logs.each do |l|
    puts "    ##{l.id} status=#{l.status} run_at=#{l.run_at&.strftime('%m-%d %H:%M')} channel=#{l.publish_channel} msg=#{l.error_msg.to_s.truncate(40)}"
  end
end

puts
puts "===== 诊断完成 ====="
