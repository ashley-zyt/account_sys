# 按最新逻辑重算系统内 KOL 的状态，纠正历史误判
#
# 只处理系统自动流转的状态（pending/contacting/replied_unprocessed/unresponsive/unreachable），
# 人工状态（reserved/negotiating/cooperating/failed）不动。
#
# 重算规则（对齐最新语义）：
#   有 replied 联系方式           -> replied_unprocessed
#   有 contacting 联系方式        -> contacting
#   有 active 且可私信            -> pending
#   有 active 但都不可私信        -> unreachable（对方关 DM / 私信关 / 平台未开发）
#   只有 unresponsive 联系方式    -> unresponsive（联系过没回）
#   其余（都 disabled / 无联系方式）-> unreachable
#
# 用法：
#   bundle exec rails runner scripts/recompute_kol_statuses.rb           # 预览
#   bundle exec rails runner scripts/recompute_kol_statuses.rb confirm   # 执行

confirm = ARGV.include?('confirm')
AUTO_STATUSES = %w[pending contacting replied_unprocessed unresponsive unreachable].freeze

def compute_status(kol)
  contacts = kol.kol_contacts
  return :replied_unprocessed if contacts.any?(&:replied?)
  return :contacting if contacts.any?(&:contacting?)
  if contacts.any?(&:active?)
    return kol.has_outreachable_contacts? ? :pending : :unreachable
  end
  contacts.any?(&:unresponsive?) ? :unresponsive : :unreachable
end

changed = []
Kol.where(status: AUTO_STATUSES).includes(:kol_contacts).find_each do |kol|
  new_status = compute_status(kol)
  next if new_status.to_s == kol.status.to_s
  changed << [kol, new_status]
end

puts "需要更新状态的 KOL：#{changed.size} 个"
changed.each do |kol, new_status|
  puts "  KOL##{kol.id} #{kol.name} #{kol.status} -> #{new_status}"
  next unless confirm
  kol.update!(status: new_status, next_action_at: nil)
end

if confirm
  puts "已更新 #{changed.size} 个 KOL 的状态"
else
  puts
  puts "以上为预览，未做任何改动。确认后执行："
  puts "  bundle exec rails runner scripts/recompute_kol_statuses.rb confirm"
end
