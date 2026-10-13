# 回填 post_stats.publish_channel：按「账号 + 日期」反查当天最后一条成功发布的渠道。
#
# url 精确反查不可靠（postforme 返回的 platform_url 与采集端真实帖子 url 格式不一致，
# 如 tiktok 主页 vs 视频、instagram reel 无用户名），改用「账号 + 发布日期 →
# 当天最后一条成功发布日志（task_logs）的 publish_channel」。
#
# 用法：
#   bundle exec rails runner scripts/backfill_post_stats_publish_channel_by_date.rb          # 预览
#   bundle exec rails runner scripts/backfill_post_stats_publish_channel_by_date.rb confirm  # 执行

confirm = ARGV.include?('confirm')

scope = PostStat.where(publish_channel: nil)
total = scope.count
puts "待回填 post_stats（publish_channel 为空）：#{total} 条"

updated = 0
scope.find_each do |ps|
  ch = PostStat.resolve_publish_channel_by_account_date(ps.account_id, ps.post_date)
  next if ch.nil?
  updated += 1
  ps.update_columns(publish_channel: ch) if confirm
end

if confirm
  puts "已回填 #{updated} 条，剩余空值 #{PostStat.where(publish_channel: nil).count} 条"
else
  puts "可回填 #{updated} 条（预览，未实际更新）"
end
