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

results = []
Account.where(platform: 'twitter').where.not(id: authorized_ids).find_each do |account|
  # 发文错误 = 该账号最近的发布失败日志（publish_channel 非空 = 发布日志，区别于养号/采集/私信）
  count = TaskLog.where(account_id: account.id, status: 'failed')
                 .where.not(publish_channel: nil)
                 .where('run_at >= ?', since)
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
