# 查询没有采集到昨日发文数据的账号，以及该账号昨日是否有发文成功任务、所属机器。
# 用途：排查「任务显示发布成功，但发文数据没采集到」的账号。
#
# 用法（服务器上）：
#   bundle exec rails runner scripts/check_missing_yesterday_stats.rb                 # 默认查昨天、仅正常状态账号
#   DATE=2026-11-08 bundle exec rails runner scripts/check_missing_yesterday_stats.rb # 指定日期
#   PLATFORM=twitter ...                                                              # 按平台过滤
#   THEME=xxx ...                                                                     # 按主题过滤
#   ALL_STATUS=1 ...                                                                  # 包含非正常状态账号
#
# 输出分组：
#   A 组（重点）：昨日无发文数据 且 昨日有成功发文任务 → 疑似「发成功但没采集到」
#   B 组：昨日无发文数据 且 昨日无成功发文任务 → 可能本来就没发，属正常

date = ENV['DATE'].present? ? Date.parse(ENV['DATE']) : Date.yesterday

scope = Account.all
scope = scope.where(status: '正常') unless ENV['ALL_STATUS'].present?
scope = scope.where(platform: ENV['PLATFORM']) if ENV['PLATFORM'].present?
scope = scope.where(theme: ENV['THEME']) if ENV['THEME'].present?

day_range = date.beginning_of_day..date.end_of_day

# 昨日有发文数据的账号集合
ids_with_stats = PostStat.where(post_date: date).distinct.pluck(:account_id).to_set

# 昨日成功发文日志（按账号快照聚合）
success_status = TaskLog.statuses[:success]
success_rows = TaskLog.where(status: success_status, run_at: day_range)
                      .where.not(account_id: nil)
                      .pluck(:account_id, :publish_channel, :run_at, :task_uuid)
success_by_account = Hash.new { |h, k| h[k] = [] }
success_rows.each { |aid, ch, run_at, uuid| success_by_account[aid] << [ch, run_at, uuid] }

no_stats = []
scope.find_each do |account|
  next if ids_with_stats.include?(account.id)

  machine_host = account.browser&.machine_host
  no_stats << {
    id: account.id,
    name: account.account_name,
    platform: account.platform,
    status: account.status,
    theme: account.theme,
    work_type: account.work_type,
    machine: machine_host || '无机器',
    profile: account.browser&.profile_name || '-',
    success_count: success_by_account[account.id].size,
    last_success: success_by_account[account.id].map { |_ch, t, _u| t }.compact.max,
    last_channel: success_by_account[account.id].map(&:first).compact.last,
    last_stat_date: account.post_stats.maximum(:post_date)
  }
end

group_a = no_stats.select { |a| a[:success_count] > 0 }
group_b = no_stats.reject { |a| a[:success_count] > 0 }

puts "=" * 90
puts "日期 #{date}（#{date.strftime('%A')}）账号总数 #{scope.count}，昨日有发文数据 #{ids_with_stats.size}，无发文数据 #{no_stats.size}"
puts "  A 组（无数据但有成功任务，重点排查）: #{group_a.size}"
puts "  B 组（无数据且无成功任务）          : #{group_b.size}"
puts "=" * 90

def channel_label(ch)
  return '-' if ch.nil?
  TaskLog.publish_channels.key(ch) || ch.to_s
end

if group_a.any?
  puts "\n【A 组】发布成功但没采集到发文数据的账号："
  printf("%-6s %-20s %-10s %-8s %-14s %-20s %-6s %-20s %-12s %s\n",
         'ID', '账号', '平台', '状态', '机器', '浏览器profile', '成功数', '最近成功时间', '渠道', '最近采集到数据的日期')
  group_a.sort_by { |a| [-a[:success_count], a[:id]] }.each do |a|
    printf("%-6d %-20s %-10s %-8s %-14s %-20s %-6d %-20s %-12s %s\n",
           a[:id], a[:name].to_s[0, 18], a[:platform], a[:status], a[:machine].to_s[0, 12],
           a[:profile].to_s[0, 18], a[:success_count],
           a[:last_success]&.strftime('%m-%d %H:%M:%S') || '-',
           channel_label(a[:last_channel]),
           a[:last_stat_date]&.to_s || '从未采集到')
  end
  puts "\nA 组成功任务明细（task_uuid，可去任务日志页查报错与回调详情）："
  group_a.each do |a|
    success_by_account[a[:id]].each do |ch, t, uuid|
      puts "  账号 #{a[:id]} #{a[:name]}: #{t&.strftime('%m-%d %H:%M:%S')} 渠道=#{channel_label(ch)} uuid=#{uuid}"
    end
  end
end

if group_b.any?
  puts "\n【B 组】昨日无数据也无成功任务的账号："
  printf("%-6s %-20s %-10s %-8s %-14s %-20s %s\n",
         'ID', '账号', '平台', '状态', '机器', '浏览器profile', '最近采集到数据的日期')
  group_b.sort_by { |a| a[:id] }.each do |a|
    printf("%-6d %-20s %-10s %-8s %-14s %-20s %s\n",
           a[:id], a[:name].to_s[0, 18], a[:platform], a[:status], a[:machine].to_s[0, 12],
           a[:profile].to_s[0, 18], a[:last_stat_date]&.to_s || '从未采集到')
  end
end

puts "\n完成。"
