# KOL 消息模块单条测试脚本（纯接口连通性测试，不落库、不改状态）
#
# 用法：
#   bin/rails runner scripts/test_kol_message.rb send  <contact_id> [account_id] [content]
#   bin/rails runner scripts/test_kol_message.rb check <contact_id> [account_id]
#
# 示例：
#   bin/rails runner scripts/test_kol_message.rb send 12
#   bin/rails runner scripts/test_kol_message.rb send 12 263 "hello, this is a test"
#   bin/rails runner scripts/test_kol_message.rb check 12 263

mode       = ARGV[0] || "send"
contact_id = ARGV[1]
account_id = ARGV[2]
content    = ARGV[3]

if contact_id.blank?
  puts "用法: bin/rails runner scripts/test_kol_message.rb send|check <contact_id> [account_id] [content]"
  exit 1
end

contact = KolContact.find_by(id: contact_id)
abort "未找到联系方式 ID=#{contact_id}" if contact.nil?

# 优先使用手动指定的账号；否则按平台自动分配；再退而求其次用任一「正常」账号
account = if account_id.present?
  Account.find_by(id: account_id)
else
  KolAccountAllocator.allocate(contact.platform) || Account.active.where(platform: contact.platform).first
end

abort "未找到可用账号（平台=#{contact.platform}），可手动指定 account_id" if account.nil?

puts "=== KOL 消息测试 ==="
puts "模式       : #{mode}"
puts "联系方式   : ##{contact.id} #{contact.platform} url=#{contact.url} nickname=#{contact.nickname}"
puts "内部账号   : ##{account.id} #{account.account_name} 平台=#{account.platform} 浏览器=#{account.browser&.profile_name}"
puts "target_url : #{contact.outreach_target_url}"
puts "-----------------------------"

case mode
when "check"
  result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)
  puts "回复状态   : #{result[:has_reply] ? '已回复' : '等待回复'}"
  replies = Array(result[:replies])
  puts "回复条数   : #{replies.size}"
  replies.each_with_index do |r, i|
    puts "  回复#{i + 1}: #{r['content'].to_s.strip}"
  end
  puts "原始返回   : #{result[:raw].inspect}"
else
  content = content.presence || "这是一条测试消息"
  puts "消息内容   : #{content}"
  result = KolOutreachApi.send_single_message(platform: contact.platform, account: account, contact: contact, content: content)
  puts "发送结果   : #{result[:success] ? '成功' : '失败'}（reason=#{result[:reason]}）"
  puts "原始返回   : #{result[:raw].inspect}"
end
