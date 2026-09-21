# ============================================================
# 诊断：某个 TikTok 账号为什么没有发布视频
# ============================================================
# 用法：
#   bundle exec rails runner scripts/diagnose_tiktok_no_publish.rb <account_id>
# 或：
#   ACCOUNT_ID=<account_id> bundle exec rails runner scripts/diagnose_tiktok_no_publish.rb
#
# 只读脚本，不修改任何数据。输出该账号「未发布」的所有可能原因：
#   1. 账号基本信息（状态/主题/工作模式/浏览器/软删除）
#   2. 浏览器信息（profile_name / machine_ip / 状态）
#   3. 调度闸门逐项检查（复现 TaskScheduler.assign_resources 的判定顺序）
#   4. 最近 7 天发文记录（post_stats）
#   5. 该账号发布任务状态分布
#   6. 待发布资源匹配情况
#   7. 最近任务日志（执行失败原因）
# ============================================================

account_id = (ARGV[0].presence || ENV['ACCOUNT_ID']).to_i
abort "用法: bundle exec rails runner scripts/diagnose_tiktok_no_publish.rb <account_id>" if account_id <= 0

account = Account.unscoped.find_by(id: account_id)
abort "账号 #{account_id} 不存在" unless account

puts "=" * 64
puts "TikTok 账号未发布诊断  (账号 ID: #{account.id})"
puts "=" * 64

# ---------- 1. 账号基本信息 ----------
puts
puts "【1. 账号基本信息】"
puts "  账号名     : #{account.account_name}"
puts "  平台       : #{account.platform}"
puts "  状态       : #{account.status}"
puts "  主题       : #{account.theme}"
puts "  工作模式   : #{account.work_type}（work_type=#{Account.work_types[account.work_type]}）"
puts "  运营人员   : #{account.operator}"
puts "  浏览器ID   : #{account.browser_id.inspect}"
puts "  最后使用   : #{account.last_used_at}"
puts "  备注       : #{account.remark}"
puts "  软删除     : #{account.deleted_at.present? ? "是（#{account.deleted_at}）" : "否"}"

# ---------- 2. 浏览器信息 ----------
puts
puts "【2. 浏览器信息】"
browser = account.browser
if browser.nil?
  puts "  ✗ 未绑定指纹浏览器（发布必须绑定浏览器）"
else
  puts "  profile_name : #{browser.profile_name}"
  puts "  machine_ip   : #{browser.machine_ip.blank? ? '（空，无法发布！）' : browser.machine_ip}"
  puts "  浏览器状态   : #{browser.status}"
  puts "  用途         : #{browser.purpose}"
  puts "  代理         : #{[browser.proxy_type, browser.proxy_host, browser.proxy_port].compact.join(' ').presence || '无'}"
end

# ---------- 3. 调度闸门检查 ----------
puts
puts "【3. 调度闸门检查（复现 TaskScheduler.assign_resources 判定顺序）】"

task_model = account.task_model_for_work_type
mode = WorkMode.all.find { |m| m.name == account.work_type }

# 3.1 工作模式是否参与自动调度
if task_model.nil?
  puts "  ✗ 工作模式「#{account.work_type}」无资源队列（不参与自动发布调度）——这本身就是未发布的原因"
else
  if mode && mode.scheduler_assign
    puts "  ✓ 工作模式「#{account.work_type}」参与自动调度（资源队列 #{task_model.name}）"
  else
    puts "  ✗ 工作模式「#{account.work_type}」未开启 scheduler_assign（不参与自动分配）"
  end

  # 3.2 账号状态
  if account.status == "正常"
    puts "  ✓ 账号状态「正常」（Account.active 通过）"
  else
    puts "  ✗ 账号状态=「#{account.status}」，非「正常」→ 不会被分配资源（这是未发布的直接原因）"
  end

  # 3.3 今天是否已发布
  today_start = Date.today.beginning_of_day
  today_end   = Date.today.end_of_day
  has_posted_today = task_model.exists?(
    account_id: account.id, status: :success, actual_publish_time: today_start..today_end
  )
  if has_posted_today
    puts "  ✓ 今天（#{Date.today}）已有发布成功记录（has_posted_today）→ 今日不会再发"
  else
    puts "  ✓ 今天尚无发布成功记录"
  end

  # 3.4 是否有待发布/执行中的任务
  active_tasks = task_model.where(account_id: account.id, status: [:waiting_publish, :executing]).order(:created_at).to_a
  if active_tasks.any?
    puts "  ✗ 已有待发布/执行中任务（has_active_task）→ 卡在这些任务上，需排查为何没执行/没完成："
    active_tasks.each do |at|
      puts "      ##{at.id} status=#{at.status} 录入于#{at.created_at} 开始执行=#{at.start_at} error=#{at.error_msg.to_s[0,40]}"
    end
  else
    puts "  ✓ 无待发布/执行中任务"
  end

  # 3.5 TikTok 零浏览量冷却
  if account.platform == "tiktok"
    range_start = Date.today - 3
    range_end   = Date.today - 1
    recent = account.post_stats.where(post_date: range_start..range_end)
    if account.zero_views_in_past_3_days?
      puts "  ✗ TikTok 零浏览量冷却：过去3天（#{range_start}~#{range_end}）发文浏览量均为0 → 暂停分配（停3天）"
      recent.each do |s|
        puts "      - #{s.post_date} #{s.title.to_s[0,40]}  views=#{s.views_count}"
      end
    else
      puts "  ✓ 未触发零浏览量冷却（过去3天窗口 #{range_start}~#{range_end}）"
    end
  end

  # 3.6 待发布资源（pending）匹配情况
  pending_count = task_model.where(status: :pending, platform: account.platform, theme: account.theme).count
  if pending_count.zero?
    puts "  ✗ 无待发布资源：#{task_model.name} 中 status=pending 且 platform=#{account.platform}、theme=#{account.theme} 的记录为 0 → 没有视频可发"
  else
    puts "  ✓ 有 #{pending_count} 条待发布资源（platform=#{account.platform}, theme=#{account.theme}）"
  end
end

# ---------- 4. 最近 7 天发文记录 ----------
puts
puts "【4. 最近 7 天发文记录（post_stats）】"
recent_stats = account.post_stats.where(post_date: (Date.today - 7)..Date.today).order(post_date: :desc)
if recent_stats.empty?
  puts "  （最近7天无发文记录）"
else
  recent_stats.each do |s|
    puts "  #{s.post_date}  #{s.title.to_s[0,36].ljust(36)}  views=#{s.views_count}  likes=#{s.likes_count}  comments=#{s.comments_count}  shares=#{s.shares_count}  更新于#{s.data_updated_at}"
  end
end
latest_stat = account.post_stats.order(data_updated_at: :desc).first
puts "  最近一次数据采集时间: #{latest_stat&.data_updated_at || '（无）'}（若很久没更新，可能是采集没跑，而非没发）"

# ---------- 5. 发布任务状态分布 ----------
if task_model
  puts
  puts "【5. 该账号发布任务状态分布（#{task_model.name}）】"
  groups = task_model.where(account_id: account.id).group(:status).count
  if groups.empty?
    puts "  （该账号没有任何发布任务记录）"
  else
    groups.sort.each do |status, count|
      puts "  #{status.to_s.ljust(16)} #{count} 条"
    end
    # 最近 5 条任务明细
    puts "  最近任务："
    task_model.where(account_id: account.id).order(created_at: :desc).limit(5).each do |t|
      puts "    ##{t.id} status=#{t.status} theme=#{t.theme} 录入于#{t.created_at} 开始执行=#{t.start_at} 发布于#{t.actual_publish_time} error=#{t.error_msg.to_s[0,50]}"
    end
  end
end

# ---------- 6. 最近任务日志 ----------
puts
puts "【6. 最近任务日志（task_logs）】"
logs = TaskLog.where(account_id: account.id).order(run_at: :desc).limit(8)
if logs.empty?
  puts "  （无日志）"
else
  logs.each do |l|
    puts "  #{l.run_at}  status=#{l.status}  error=#{l.error_msg.to_s[0,60]}  task_uuid=#{l.task_uuid}"
  end
end

puts
puts "=" * 64
puts "诊断结束。对照【3】里标记 ✗ 的项，即为该账号未发布的原因。"
puts "=" * 64
