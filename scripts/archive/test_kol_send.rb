# 单独测试某个 KOL 的消息发送功能（真实发送，会调用运营机器发私信）
#
# 用法：
#   bundle exec rails runner scripts/test_kol_send.rb <KOL_ID>                  # 走首次触达模板自动发送
#   bundle exec rails runner scripts/test_kol_send.rb <KOL_ID> "测试内容"       # 指定消息内容
#   bundle exec rails runner scripts/test_kol_send.rb <KOL_ID> "" 17 123        # 指定 内容+渠道ID+账号ID
#
# 参数（按顺序）：
#   1. KOL_ID       必填
#   2. 消息内容      可选，缺省走首次触达模板（模板缺变量会报错）
#   3. 联系方式ID    可选，缺省取「当前联系渠道」，不管是否已联系过（临时测试用）
#   4. 账号ID       可选，缺省自动分配一个可用内部账号
#
# 注意：这是真实发送，会给对方真的发一条私信，请确认无误后再执行。

kol_id    = ARGV[0].to_s.strip
content   = ARGV[1]
contact_id = ARGV[2].to_s.strip
account_id = ARGV[3].to_s.strip

if kol_id.blank?
  puts "用法: bundle exec rails runner scripts/test_kol_send.rb <KOL_ID> [消息内容] [contact_id] [account_id]"
  exit 1
end

kol = Kol.find_by(id: kol_id)
if kol.nil?
  puts "未找到 KOL##{kol_id}"
  exit 1
end

puts "===== KOL 信息 ====="
puts "  ID: #{kol.id}  名称: #{kol.name}  状态: #{kol.status_label}"
puts "  联系方式:"
kol.kol_contacts.each do |c|
  puts "    - ##{c.id} #{c.platform} #{c.nickname.presence || '-'} 可发私信=#{c.messaging_enabled} 状态=#{c.status_label}"
end

contact = nil
if contact_id.present?
  contact = kol.kol_contacts.find_by(id: contact_id)
  if contact.nil?
    puts "未找到联系方式 ##{contact_id}（该 KOL 的联系方式见上方列表）"
    exit 1
  end
else
  # 【临时测试】不管是否联系过都可继续发：
  # 优先用当前联系渠道，否则取优先级最高的可发私信渠道（不再限定 status=未联系）
  contact = kol.current_contact || kol.kol_contacts.where(messaging_enabled: true).order(:priority, :id).first
  if contact.nil?
    puts "该 KOL 没有可发私信的联系方式"
    exit 1
  end
end

account = nil
if account_id.present?
  account = Account.find_by(id: account_id)
  if account.nil?
    puts "未找到账号 ##{account_id}"
    exit 1
  end
end

puts ""
puts "===== 开始发送（真实发送）====="
puts "  消息内容: #{content.present? ? content : '(走首次触达模板)'}"
puts "  渠道: #{contact ? "##{contact.id} #{contact.platform}" : '(自动选优先级最高)'}"
puts "  账号: #{account ? "##{account.id} #{account.account_name}" : '(自动分配)'}"

result = KolScheduler.manual_contact(kol, contact: contact, account: account, content: content.presence)

puts ""
puts "===== 结果 ====="
if result[:ok]
  msg = kol.latest_outgoing_message
  puts "发送成功"
  puts "  消息内容: #{msg&.content}"
  puts "  使用账号: #{msg&.account&.account_name || '-'}"
  puts "  渠道: #{msg&.kol_contact&.platform || '-'}"
else
  puts "发送失败: #{result[:error]}"
end
