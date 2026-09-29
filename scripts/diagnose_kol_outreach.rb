# ===== 诊断 KOL 触达执行情况（排查「为什么只有 N 个联系中」）=====
# 用法：bundle exec rails runner scripts/diagnose_kol_outreach.rb

today = Time.current.beginning_of_day..Time.current.end_of_day

puts "==== 1. KOL 状态分布 ===="
Kol.group(:status).count.each { |k, v| puts "  #{k}: #{v}" }
puts

puts "==== 2. 联系方式状态分布 ===="
KolContact.group(:status).count.each { |k, v| puts "  #{k}: #{v}" }
puts

puts "==== 3. 联系方式平台分布 ===="
KolContact.group(:platform).count.each { |k, v| puts "  #{k}: #{v}" }
puts

puts "==== 4. 今日消息发送 ===="
puts "  成功(sent_success): #{KolMessage.where(status: :sent_success, created_at: today).count}"
puts "  失败(sent_failed): #{KolMessage.where(status: :sent_failed, created_at: today).count}"
puts "  待发(queued): #{KolMessage.where(status: :queued).count}"
puts

puts "==== 5. 今日失败消息错误分布 ===="
KolMessage.where(status: :sent_failed, created_at: today).group(:error_msg).count.each do |k, v|
  puts "  #{k.to_s.truncate(70)}: #{v}"
end
puts

puts "==== 6. 账号今日发送成功数（前 20）===="
KolMessage.where(status: :sent_success, direction: :outgoing, created_at: today)
  .group(:account_id).count.sort_by { |_, v| -v }.first(20).each do |aid, cnt|
  a = Account.find_by(id: aid)
  puts "  account=#{aid} #{a&.account_name} platform=#{a&.platform} X认证=#{a&.x_credential&.authorized?} 今日发=#{cnt}"
end
puts

puts "==== 7. 待联系(pending) KOL 的 next_action_at 分布 ===="
Kol.where(status: :pending).group(:next_action_at).count.each { |k, v| puts "  #{k.inspect}: #{v}" }
puts

puts "==== 8. 待联系 KOL 的可触达性分析 ===="
pending = Kol.where(status: :pending)
contactable = 0
reasons = Hash.new(0)
pending.find_each do |kol|
  if kol.has_outreachable_contacts?
    contactable += 1
  else
    has_active = kol.kol_contacts.where(status: :active).exists?
    has_msgenabled = kol.kol_contacts.where(status: :active, messaging_enabled: true).exists?
    has_supported = kol.kol_contacts.where(status: :active, messaging_enabled: true)
                          .any? { |c| KolAccountAllocator.supported_platform?(c.platform) }
    if !has_active
      reasons['无 active 联系方式（已停用/已回复等）'] += 1
    elsif !has_msgenabled
      reasons['active 但 messaging_enabled=false'] += 1
    elsif !has_supported
      reasons['平台不支持（email/telegram/whatsapp/linkedin 等）'] += 1
    else
      reasons['其它'] += 1
    end
  end
end
puts "  可触达: #{contactable} / 不可触达: #{pending.count - contactable}"
reasons.each { |k, v| puts "    - #{k}: #{v}" }
