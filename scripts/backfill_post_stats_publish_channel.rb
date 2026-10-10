# 回填 post_stats.publish_channel（按 url 精确匹配 postforme/x_api，匹配不到留空）
#
# 用法：
#   bundle exec rails runner scripts/backfill_post_stats_publish_channel.rb          # 回填全部空值
#   bundle exec rails runner scripts/backfill_post_stats_publish_channel.rb 100      # 只回填最近 N 条空值

limit_arg = ARGV[0].to_i

scope = PostStat.where(publish_channel: nil)
scope = scope.order(id: :desc).limit(limit_arg) if limit_arg > 0

count = 0
scope.find_each do |ps|
  ch = PostStat.resolve_publish_channel(ps.url)
  next if ch.nil?
  ps.update_column(:publish_channel, ch)
  count += 1
end

puts "回填了 #{count} 条 post_stats.publish_channel（剩余空值 #{PostStat.where(publish_channel: nil).count} 条）"
