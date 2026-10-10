# 查询「最近发文错误从高到低」的 Twitter 账号（尚未完成 X 授权）
#
# 用途：找出浏览器发布失败较多、还没切 x_api 的 Twitter 账号，优先做 X 授权
#
# 用法：
#   bundle exec rails runner scripts/twitter_unauthed_error_accounts.rb          # 最近 7 天
#   bundle exec rails runner scripts/twitter_unauthed_error_accounts.rb 30       # 最近 30 天

days = (ARGV[0] || 7).to_i
since = days.days.ago

# 已完成 X 授权的账号 ID（这些不算「还没授权」）
authorized_ids = XCredential.where(auth_status: XCredential.auth_statuses[:authorized]).pluck(:account_id)

# 发文日志判定：task_uuid 属于任一资源队列任务即视为「发文」日志。
# （旧日志没记录 publish_channel，也能靠 task_uuid 识别；养号/采集/私信/巡检的 task_uuid 不属于资源表，会被排除）
resource_conditions = WorkMode.resource_modes.map { |m|
  "EXISTS (SELECT 1 FROM #{m.association_name} _t WHERE _t.task_uuid = task_logs.task_uuid)"
}
publish_sql = "(#{resource_conditions.join(' OR ')})"

results = []
Account.where(platform: 'twitter').where.not(id: authorized_ids).find_each do |account|
  count = TaskLog.where(account_id: account.id, status: 'failed')
                 .where('run_at >= ?', since)
                 .where(publish_sql)
                 .count
  results << [account, count] if count > 0
end

results.sort_by! { |_, c| -c }

puts "最近 #{days} 天发文失败的未授权 Twitter 账号（按错误次数从高到低）："
if results.empty?
  puts "无符合条件的账号"
else
  results.each do |account, count|
    puts "##{account.id}\t#{account.account_name}\t#{count} 次\t首选渠道=#{account.publish_channel.presence || '默认'}"
  end
end
