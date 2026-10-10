# 回填 post_stats.publish_channel：把「已授权 postforme」账号在 2025-09-24 之后采集到的、
# 且当前 publish_channel 为空的记录，标记为 postforme 渠道。
#
# 背景：publish_channel 字段上线后改为记录实际发布渠道，但历史数据未回填，
#       导致之前通过 postforme 发布的数据渠道为空，统计/筛选时缺失。
#
# 执行：bundle exec rails runner scripts/backfill_post_stats_postforme_channel.rb
#
# 口径：
#   - 账号范围：当前已授权 postforme 的账号（Account#postforme_authorized? 为 true）
#   - 时间范围：post_date >= 2025-09-24
#   - 只更新 publish_channel 为 NULL 的记录（已识别渠道的保留不动）

START_DATE = Date.new(2025, 9, 24)

# 找出已授权 postforme 的账号 id（排除 twitter，twitter 用 x_api）
# 通过 postforme_accounts 表 join 判断，避免逐条 Ruby 过滤的性能和兼容问题
postforme_account_ids = Account.joins(:postforme_account)
  .where.not(platform: 'twitter')
  .where(postforme_accounts: { auth_status: PostformeAccount.auth_statuses[:authorized] })
  .pluck(:id)

puts "已授权 postforme 的账号数：#{postforme_account_ids.size}"

if postforme_account_ids.empty?
  puts "无符合条件的账号，退出"
  exit 0
end

# 统计待更新条数
scope = PostStat.where(account_id: postforme_account_ids)
                .where(post_date: START_DATE..)
                .where(publish_channel: nil)

total = scope.count
puts "待回填的 post_stats 条数：#{total}"

if total.zero?
  puts "无待回填数据，退出"
  exit 0
end

# 批量更新，每批 1000 条避免大事务
batch_size = 1000
updated = 0
scope.in_batches(of: batch_size) do |batch|
  n = batch.update_all(publish_channel: Account.publish_channels['postforme'])
  updated += n
  puts "已更新 #{updated}/#{total}"
end

puts "回填完成，共更新 #{updated} 条 post_stats 记录"
