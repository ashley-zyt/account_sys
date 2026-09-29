# 盘点「待联系/联系中 但没有任何可私信联系方式」的 KOL
# 这些 KOL 在下次 KolScheduler.run 时会被标记为「无法联系(unreachable)」
# 用法：bundle exec rails runner scripts/diagnose_unreachable_kols.rb

puts "=== pending/contacting 但无可私信联系方式的 KOL（将被标记「无法联系」）==="
targets = Kol.where(status: [:pending, :contacting]).select { |k| !k.has_outreachable_contacts? }
puts "共 #{targets.size} 个"
targets.each do |k|
  platforms = k.kol_contacts.map { |c| "#{c.platform}(#{c.status}#{c.messaging_enabled? ? '' : ',私信关'})" }.join('、')
  puts "  KOL##{k.id} #{k.name} 状态=#{k.status} 联系方式=[#{platforms}]"
end

puts
puts "=== KOL 各状态分布 ==="
Kol.statuses.each_key { |key| puts "  #{key}: #{Kol.where(status: key).count}" }
