# 批量打开 Instagram 联系方式的「可发私信」，并重算受影响 KOL 的状态
#
# 场景：之前把 Instagram 联系方式的 messaging_enabled 批量设成了 false，
#       导致部分 KOL（只有 ins 一个可私信渠道）被判定为「无法联系」。
#       现在统一打开，并让这些 KOL 重新进入触达队列。
#
# 用法（在 account_sys 服务器上跑）：
#   预览（只列出，不改数据）：
#     bundle exec rails runner scripts/enable_instagram_dm.rb
#   执行（打开 + 重算）：
#     bundle exec rails runner scripts/enable_instagram_dm.rb confirm

confirm = ARGV.include?('confirm')

contacts = KolContact.where(platform: :instagram, messaging_enabled: false)

puts "=== Instagram 私信关闭的联系方式 ==="
puts "共 #{contacts.size} 个（platform=instagram 且 messaging_enabled=false）"
puts "按状态分布："
contacts.group(:status).count.each { |s, c| puts "  #{s}: #{c}" }
puts

kol_ids = contacts.distinct.pluck(:kol_id)
kols = Kol.where(id: kol_ids).to_a
unreachable_kols = kols.select(&:unreachable?)

puts "涉及 KOL #{kols.size} 个"
puts "其中当前状态「无法联系」的 #{unreachable_kols.size} 个（打开后具备触达条件即可重新入队）"
unreachable_kols.each do |k|
  cs = k.kol_contacts.map { |c| "#{c.platform}(#{c.status}#{c.messaging_enabled? ? '' : ',私信关'})" }.join('、')
  puts "  KOL##{k.id} #{k.name}  联系方式=[#{cs}]"
end

if confirm
  opened = contacts.update_all(messaging_enabled: true)
  puts "\n已打开 #{opened} 个 Instagram 联系方式的「可发私信」"

  reenqueued = 0
  Kol.where(id: kol_ids).includes(:kol_contacts).find_each do |kol|
    next unless %w[unreachable unresponsive].include?(kol.status.to_s)
    reenqueued += 1 if kol.enqueue!
  end
  puts "重新入队 #{reenqueued} 个 KOL（转为待联系，等调度器用绑定了浏览器的 Ins 账号发私信）"
else
  puts "\n以上为预览，未改动任何数据。"
  puts "执行：bundle exec rails runner scripts/enable_instagram_dm.rb confirm"
end
