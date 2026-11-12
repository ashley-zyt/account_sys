# 平台开发了私信功能后，把「无法联系」但现已具备可触达联系方式的 KOL 恢复为「待联系」
#
# 场景：系统后续开发了某平台的私信（如 linkedin 加入 KolAccountAllocator::SUPPORTED_PLATFORMS），
#       之前因该平台不支持而标 unreachable 的 KOL，现在 has_outreachable_contacts? 变 true，需要恢复。
# 对方关 DM（联系方式已 disabled）的 KOL 不会恢复（disabled 非 active，不在可触达范围内）。
#
# 用法：
#   bundle exec rails runner scripts/restore_unreachable_kols.rb           # 预览
#   bundle exec rails runner scripts/restore_unreachable_kols.rb confirm   # 执行

confirm = ARGV.include?('confirm')

targets = Kol.includes(:kol_contacts).where(status: :unreachable).select { |k| k.has_outreachable_contacts? }

puts "可恢复的「无法联系」KOL（现已有可触达联系方式）：#{targets.size} 个"
targets.each do |k|
  contacts = k.kol_contacts.map { |c| "#{c.platform}(#{c.status})" }.join('、')
  puts "  KOL##{k.id} #{k.name} 联系方式=[#{contacts}]"
  next unless confirm
  k.update!(status: :pending, next_action_at: nil)
end

if confirm
  puts "已恢复 #{targets.size} 个 KOL 为「待联系」"
else
  puts "以上为预览。确认后加 confirm 参数执行："
  puts "  bundle exec rails runner scripts/restore_unreachable_kols.rb confirm"
end
