# 检查近 N 日（默认 7）「浏览器（ag_center）发布失败」次数超过阈值（默认 7 次）的账号。
# 用途：定位高频发布失败的账号，结合错误信息排查（未登录/封禁/页面异常等）。
#
# 用法（服务器上）：
#   bundle exec rails runner scripts/check_browser_publish_failures.rb                     # 近7天、失败>7次
#   DAYS=14 THRESHOLD=10 bundle exec rails runner scripts/check_browser_publish_failures.rb
#   PLATFORM=instagram ...                                                                 # 按平台过滤
#
# 说明：
#   - 「浏览器发布」= task_logs.publish_channel = ag_center（浏览器模拟）
#   - 按账号日志快照（account_id）统计，任务被释放资源也能算到当时执行失败的头账号上

days = (ENV['DAYS'] || 7).to_i
threshold = (ENV['THRESHOLD'] || 7).to_i
platform = ENV['PLATFORM'].presence

range_start = days.days.ago.beginning_of_day
range_end = Time.current

base = TaskLog.where(status: :failed, publish_channel: :ag_center, run_at: range_start..range_end)
base = base.joins('INNER JOIN accounts ON accounts.id = task_logs.account_id')
           .where(accounts: { platform: platform }) if platform

# 按账号聚合计数
counts = base.group(:account_id).count
fail_detail = base.group(:account_id, :error_msg).count

hit = counts.select { |_aid, cnt| cnt > threshold }.sort_by { |_aid, cnt| -cnt }

puts '=' * 100
puts "近 #{days} 天（#{range_start.strftime('%Y-%m-%d')} ~ #{range_end.strftime('%Y-%m-%d')}）浏览器发布失败 > #{threshold} 次的账号：#{hit.size} 个"
puts '=' * 100

if hit.empty?
  puts '无命中账号。'
else
  printf("%-6s %-20s %-10s %-10s %-14s %-8s %-8s %s\n",
         'ID', '账号', '平台', '状态', '机器', '失败次数', '成功次数', '高频错误TOP3')
  hit.each do |aid, cnt|
    account = Account.find_by(id: aid)
    next if account.nil? # 账号已删除（软删除也被 default_scope 过滤）

    success_cnt = TaskLog.where(status: :success, publish_channel: :ag_center, account_id: aid, run_at: range_start..range_end).count
    top_errors = fail_detail.select { |(id, _), _| id == aid }
                            .sort_by { |_, c| -c }
                            .first(3)
                            .map { |(_, msg), c| "#{(msg || '空').to_s[0, 40]}(#{c})" }
                            .join(' ; ')
    printf("%-6d %-20s %-10s %-10s %-14s %-8d %-8d %s\n",
           account.id, account.account_name.to_s[0, 18], account.platform, account.status,
           account.browser&.machine_host.to_s[0, 12], cnt, success_cnt, top_errors)
  end
end

puts "\n完成。"
