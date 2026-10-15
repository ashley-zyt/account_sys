# ===== 定位「发文 publish_channel 大量未匹配(nil)」断点 =====
# 分层排查：渠道未匹配，问题只可能在 3 个环节之一：
#   (1) task_logs 本身没记 publish_channel（发布写入端没带渠道）
#   (2) resolve_publish_channel_by_account_date 查不到匹配（时间窗口/查询逻辑）
#   (3) 查到了但写回 post_stats 失败（类型转换）
#
# 用法（服务器上，项目根目录）：
#   bundle exec rails runner scripts/diagnose_publish_channel_gap.rb
#   bundle exec rails runner scripts/diagnose_publish_channel_gap.rb 3 8   # 近3天，抽8个样本
#
# 参数：窗口天数（默认3）、nil 样本数（默认8）

window_days = (ARGV[0] || 3).to_i
sample_size = (ARGV[1] || 8).to_i
since = window_days.days.ago

puts "==================== 1. 近 #{window_days} 天入库 PostStat 渠道分布 ===================="
dist = PostStat.where("data_updated_at >= ?", since).group(:publish_channel).count
dist.sort_by { |k, _| k.to_s }.each { |k, v| puts "  #{k.inspect} => #{v}" }
total = dist.values.sum.to_i
nil_count = PostStat.where("data_updated_at >= ? AND publish_channel IS NULL", since).count
puts "  总计=#{total}  nil(未匹配)=#{nil_count}  匹配率=#{(100.0 * (total - nil_count) / total).round(1)}%"
puts

puts "==================== 2. nil 样本逐条反查 task_logs ===================="
samples = PostStat.where("data_updated_at >= ? AND publish_channel IS NULL", since)
                  .order(data_updated_at: :desc)
                  .limit(sample_size)

if samples.empty?
  puts "  近 #{window_days} 天没有 nil 样本（可能已全部匹配）"
else
  samples.each do |ps|
    puts "  --- PostStat id=#{ps.id} account_id=#{ps.account_id} post_date=#{ps.post_date} url=#{ps.url.to_s.truncate(50)}"
    # 环节(2)：±1 天窗口内，success + channel 非空
    day_start = (ps.post_date - 1.day).beginning_of_day
    day_end   = (ps.post_date + 1.day).end_of_day
    logs = TaskLog.where(account_id: ps.account_id)
                  .where.not(publish_channel: nil)
                  .where(status: TaskLog.statuses[:success])
                  .where(run_at: day_start..day_end)
                  .order(run_at: :desc)
                  .limit(5)

    if logs.any?
      puts "    ✓ ±1天窗口内有成功发布日志 #{logs.size} 条（→ 环节2查得到，问题在环节3写回）:"
      logs.each { |l| puts "        run_at=#{l.run_at&.strftime('%m-%d %H:%M')} channel=#{l.publish_channel.inspect} task_uuid=#{l.task_uuid}" }
      next
    end

    # 环节(2)窗口扩到 ±3 天：判断是「时间错位」还是「根本没记录」
    wide_start = (ps.post_date - 3.days).beginning_of_day
    wide_end   = (ps.post_date + 3.days).end_of_day
    wider = TaskLog.where(account_id: ps.account_id)
                   .where.not(publish_channel: nil)
                   .where(status: TaskLog.statuses[:success])
                   .where(run_at: wide_start..wide_end)
                   .order(run_at: :desc)
                   .limit(5)
    if wider.any?
      puts "    ✗ ±1天查不到，但±3天有（→ 时间错位超±1天，窗口需再放宽）:"
      wider.each { |l| puts "        run_at=#{l.run_at&.strftime('%m-%d %H:%M')} channel=#{l.publish_channel.inspect}" }
    else
      # 环节(1)：再看该账号最近有没有任何成功「发布」日志（不限渠道），区分是没发布还是没带渠道
      any_success = TaskLog.where(account_id: ps.account_id, status: TaskLog.statuses[:success])
                           .where(run_at: wide_start..wide_end)
                           .order(run_at: :desc).limit(3)
      if any_success.any?
        puts "    ✗ ±3天有成功日志但 publish_channel 全为 nil（→ 环节1：发布写入端没带渠道）:"
        any_success.each { |l| puts "        run_at=#{l.run_at&.strftime('%m-%d %H:%M')} channel=#{l.publish_channel.inspect} task_uuid=#{l.task_uuid}" }
      else
        puts "    ✗ ±3天账号无任何成功发布日志（→ 采集数据与发布日志完全对不上：账号/日期错位 或 该帖子非本系统发布）"
      end
    end
  end
end
puts

puts "==================== 3. 自测 resolve 方法（确认代码已生效且类型正确） ===================="
# 取一个已知成功发布的账号+日期，验证返回整数渠道
test_log = TaskLog.where.not(publish_channel: nil).where(status: TaskLog.statuses[:success])
                  .where.not(run_at: nil).order(run_at: :desc).first
if test_log
  val = PostStat.resolve_publish_channel_by_account_date(test_log.account_id, test_log.run_at.to_date)
  puts "  账号 #{test_log.account_id} 日期 #{test_log.run_at.to_date}："
  puts "    task_log 原始 channel=#{test_log.publish_channel.inspect}"
  puts "    resolve 返回=#{val.inspect}（应为整数 0/1/2/3，字符串说明代码未生效或枚举转换丢失）"
else
  puts "  task_logs 里没有任何带渠道的成功日志，无法自测"
end
puts

puts "==================== 结论判断 ===================="
if nil_count == 0
  puts "  近 #{window_days} 天无 nil，匹配正常"
elsif (100.0 * (total - nil_count) / total) > 80
  puts "  匹配率尚可，聚焦上面「✗」样本定位剩余未匹配原因"
else
  puts "  匹配率偏低，按上面样本命中的环节（1/2/3）修对应层"
end