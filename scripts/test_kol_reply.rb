# 临时获取某个 KOL 的回复消息（实时调用运营机器 check_reply 接口，只查询不落库）
#
# 用法：
#   bundle exec rails runner scripts/test_kol_reply.rb <KOL_ID>           # 查该 KOL 所有「已联系」渠道
#   bundle exec rails runner scripts/test_kol_reply.rb <KOL_ID> 17        # 指定联系方式ID
#
# 参数：
#   1. KOL_ID       必填
#   2. 联系方式ID    可选，缺省遍历该 KOL 所有「已联系·等回复」的渠道

kol_id    = ARGV[0].to_s.strip
contact_id = ARGV[1].to_s.strip

if kol_id.blank?
  puts "用法: bundle exec rails runner scripts/test_kol_reply.rb <KOL_ID> [contact_id]"
  exit 1
end

kol = Kol.find_by(id: kol_id)
if kol.nil?
  puts "未找到 KOL##{kol_id}"
  exit 1
end

puts "===== KOL 信息 ====="
puts "  ID: #{kol.id}  名称: #{kol.name}  状态: #{kol.status_label}"

# 已落库的历史回复（供对照）
incoming = kol.kol_messages.where(direction: :incoming).order(:id)
if incoming.any?
  puts ""
  puts "===== 已落库的回复（#{incoming.size} 条）====="
  incoming.each do |m|
    puts "  [#{m.occurred_at&.strftime('%m-%d %H:%M') || m.created_at&.strftime('%m-%d %H:%M')}] #{m.kol_contact&.platform} #{m.content}"
  end
else
  puts ""
  puts "===== 已落库的回复：暂无 ====="
end

contacts = if contact_id.present?
  c = kol.kol_contacts.find_by(id: contact_id)
  if c.nil?
    puts "未找到联系方式 ##{contact_id}"
    exit 1
  end
  [c]
else
  # 默认查「已联系·等回复」的渠道（这些才可能有回复）
  kol.kol_contacts.where(status: KolContact.statuses[:contacting]).to_a
end

if contacts.empty?
  puts ""
  puts "没有「已联系·等回复」的渠道（可用第 2 个参数指定 contact_id 强制查询）"
  exit 0
end

contacts.each do |contact|
  puts ""
  puts "===== 实时查询 渠道##{contact.id} #{contact.platform} #{contact.nickname.presence || '-'} ====="
  account = contact.last_outgoing_account
  if account.nil?
    puts "  无「发送成功」的内部账号记录，无法查询回复"
    next
  end
  puts "  使用账号: ##{account.id} #{account.account_name}"

  result = KolOutreachApi.check_reply(platform: contact.platform, account: account, contact: contact)

  if result[:has_reply]
    replies = Array(result[:replies])
    puts "  有回复！共 #{replies.size} 条："
    replies.each_with_index do |r, i|
      time = r["observed_at"] || r["time"] || r["created_at"]
      puts "    [#{i + 1}] #{time} #{r["content"]}"
    end
  else
    puts "  暂无回复（对方还没回，或回复尚未被采集端抓到）"
  end

  if result[:error].present?
    puts "  接口错误: #{result[:error]}"
  end
end
