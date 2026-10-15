# ===== 确认发布渠道未匹配的根因 =====
# 输出三组数据，用于确定回填规则：
#   1) task_log 最早带渠道的时间（渠道写入功能上线时间点）
#   2) nil 帖子的 post_date 月份分布（判断是否集中在历史旧日期）
#   3) 无渠道的成功日志按 task_uuid 前2位分布（判断旧发布是否都是剪映/浏览器）
#
# 用法（服务器上）：
#   bundle exec rails runner scripts/confirm_channel_gap_root_cause.rb

cutoff = TaskLog.where.not(publish_channel: nil).minimum(:run_at)
puts "1) task_log 最早带渠道时间: #{cutoff}"
puts

puts "2) nil post_stat 按 post_date 月份分布："
PostStat.where(publish_channel: nil)
        .group(Arel.sql("DATE_FORMAT(post_date, '%Y-%m')"))
        .count
        .sort.each { |k, v| puts "  #{k} => #{v}" }
puts

puts "3) 成功日志(无渠道) 按 task_uuid 前2位分布："
TaskLog.where(status: TaskLog.statuses[:success])
       .where(publish_channel: nil)
       .group(Arel.sql("SUBSTRING(task_uuid,1,2)"))
       .count
       .sort_by { |k, _| k.to_s }
       .each { |k, v| puts "  #{k.inspect} => #{v}" }
puts

puts "4) 已匹配渠道的分布（对照）："
PostStat.where.not(publish_channel: nil)
        .group(:publish_channel)
        .count
        .sort.each { |k, v| puts "  #{k.inspect} => #{v}" }