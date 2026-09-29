# 批量把「只有一个联系方式 且 不能私信」的 KOL 标记为「无法联系(unreachable)」
#
# 「不能私信」判定（唯一联系方式）：
#   - 未联系(active) 但私信开关关(messaging_enabled=false)
#   - 未联系(active) 但平台不支持私信（linkedin/youtube/email 等）
#   - 已停用(disabled)
# 排除：已联系过(contacting/replied/unresponsive)——那些属于「等回复/已回复/未回复」，不算「不能私信」。
#
# 用法：
#   bundle exec rails runner scripts/mark_single_unreachable_kols.rb           # 预览
#   bundle exec rails runner scripts/mark_single_unreachable_kols.rb confirm   # 执行

confirm = ARGV.include?('confirm')

def single_contact_unsendable?(kol)
  return false unless kol.kol_contacts.size == 1
  c = kol.kol_contacts.first
  return false if %w[contacting replied unresponsive].include?(c.status.to_s)
  return true if c.disabled?
  !c.messaging_enabled? || !KolAccountAllocator.supported_platform?(c.platform)
end

def unsendable_reason(kol)
  c = kol.kol_contacts.first
  return "已停用" if c.disabled?
  return "私信关" unless c.messaging_enabled?
  "平台不支持(#{c.platform})"
end

targets = Kol.includes(:kol_contacts).select { |k| single_contact_unsendable?(k) && !k.unreachable? }

puts "符合条件的 KOL（唯一联系方式且不能私信，当前非「无法联系」）：#{targets.size} 个"
targets.each do |k|
  c = k.kol_contacts.first
  puts "  KOL##{k.id} #{k.name} 状态=#{k.status} 联系方式=[#{c.platform}/#{c.status}] 原因=#{unsendable_reason(k)}"
  next unless confirm
  k.update!(status: :unreachable, next_action_at: nil)
end

if confirm
  puts "已标记 #{targets.size} 个 KOL 为「无法联系」"
else
  puts "以上为预览。确认后加 confirm 参数执行："
  puts "  bundle exec rails runner scripts/mark_single_unreachable_kols.rb confirm"
end
