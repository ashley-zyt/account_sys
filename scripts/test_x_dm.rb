# ===== 测试 X API 私信（解析 user_id / 发私信 / 拉消息）=====
# 用法（在 account_sys 服务器上跑）：
#   只解析 user_id（不发）：
#     bundle exec rails runner scripts/test_x_dm.rb <account_id> <contact_id>
#   发一条测试私信：
#     bundle exec rails runner scripts/test_x_dm.rb <account_id> <contact_id> send <内容>
#   拉最近消息：
#     bundle exec rails runner scripts/test_x_dm.rb <account_id> <contact_id> replies

account_id = ARGV[0].to_i
contact_id = ARGV[1].to_i
action = ARGV[2] || 'resolve'

account = Account.find_by(id: account_id)
abort "账号 #{account_id} 不存在" unless account

contact = KolContact.find_by(id: contact_id)
abort "联系方式 #{contact_id} 不存在" unless contact

puts "账号: #{account.id} #{account.account_name} platform=#{account.platform}"
xc = account.x_credential
puts "X认证: #{xc ? "auth_status=#{xc.auth_status} x_user_id=#{xc.x_user_id}" : '无凭证'}"
puts "联系方式: #{contact.id} platform=#{contact.platform} url=#{contact.url} channel=#{contact.outreach_channel} x_user_id=#{contact.x_user_id}"
puts

token = XAuthService.access_token_for(account)
if token.blank?
  puts "✗ 拿不到有效 token（未认证或 token 失效）"
  exit
end
puts "✓ 拿到 token: #{token[0, 8]}..."

# 解析 user_id（优先缓存）
pid = contact.x_user_id
if pid.blank?
  username = contact.url.to_s.sub(/\A@/, '')
  resp = XApi.user_by_username(access_token: token, username: username)
  if XApi.success?(resp)
    pid = resp.dig(:body, 'data', 'id').to_s
    puts "✓ 解析 user_id: @#{username} → #{pid}"
  else
    puts "✗ 解析 user_id 失败: code=#{resp[:code]} raw=#{resp[:raw].to_s.truncate(200)}"
    exit
  end
end

case action
when 'send'
  content = ARGV[3..].to_a.join(' ')
  abort '请提供发送内容' if content.blank?
  resp = XApi.send_dm(access_token: token, participant_id: pid, text: content)
  puts XApi.success?(resp) ? "✓ 发送成功" : "✗ 发送失败: code=#{resp[:code]} raw=#{resp[:raw].to_s.truncate(300)}"
when 'replies'
  resp = XApi.dm_events(access_token: token, participant_id: pid, max_results: 50)
  if XApi.success?(resp)
    events = Array(resp.dig(:body, 'data'))
    puts "✓ 拉到 #{events.size} 条事件"
    events.each do |ev|
      puts "  [#{ev['event_type']}] sender=#{ev['sender_id']} at=#{ev['created_at']} text=#{ev['text'].to_s.truncate(60)}"
    end
  else
    puts "✗ 拉消息失败: code=#{resp[:code]} raw=#{resp[:raw].to_s.truncate(300)}"
  end
end
