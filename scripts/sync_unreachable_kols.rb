# 批量修复「无法联系(unreachable) 但现在已具备触达条件」的 KOL
#
# 场景：联系方式从 disabled 恢复成 active 后，KOL 状态没被重新评估，卡在 unreachable。
#   （例如 541 误判停用联系方式 → KOL 转 unreachable → 后来恢复 contact，但 KOL 没重算）
#
# 判定：unreachable 且 ready_for_outreach?（active 可私信联系方式 + 变量完整）
#
# 用法（在 account_sys 服务器上跑）：
#   预览（只列出，不改数据）：
#     bundle exec rails runner scripts/sync_unreachable_kols.rb
#   执行（转回待联系）：
#     bundle exec rails runner scripts/sync_unreachable_kols.rb confirm

confirm = ARGV.include?('confirm')

targets = Kol.where(status: :unreachable).select { |k| k.ready_for_outreach? }

puts "=== unreachable 但现在已具备触达条件的 KOL ==="
puts "共 #{targets.size} 个"
targets.each do |k|
  contacts = k.kol_contacts.map { |c| "#{c.platform}(#{c.status})" }.join('、')
  puts "  KOL##{k.id} #{k.name}  联系方式=[#{contacts}]"
end

if confirm
  n = 0
  targets.each { |k| n += 1 if k.enqueue! }
  puts "\n完成：重新入队 #{n} 个 KOL"
else
  puts "\n以上为预览，未改动任何数据。"
  puts '执行：bundle exec rails runner scripts/sync_unreachable_kols.rb confirm'
end
