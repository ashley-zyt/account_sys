# 把「对方已关闭私信」的联系方式更新为停用(disabled)
# 与 403「对方拒绝私信」的自动处理保持一致（status=disabled）
# 用法：
#   bundle exec rails runner scripts/mark_dm_closed_contacts.rb --ids=1,2,3            # 预览
#   bundle exec rails runner scripts/mark_dm_closed_contacts.rb --ids=1,2,3 confirm    # 执行
#
# 也支持不传 --ids，改为 --all 预览所有 active 的 twitter 联系方式（谨慎，仅预览）

ids = []
confirm = ARGV.include?('confirm')
ARGV.each do |a|
  ids = a.split('=')[1].split(',').map(&:to_i).reject(&:zero?) if a.start_with?('--ids=')
end

contacts =
  if ids.any?
    KolContact.where(id: ids).order(:id)
  elsif ARGV.include?('--all')
    KolContact.where(status: :active).order(:id)
  else
    []
  end

if contacts.empty?
  puts "未找到目标联系方式。用法：--ids=1,2,3（指定）或 --all（所有 active，仅预览建议）"
  exit
end

puts "待停用（对方关私信）的联系方式：#{contacts.count} 个"
contacts.each do |c|
  puts "  contact=#{c.id} platform=#{c.platform} url=#{c.url} 当前status=#{c.status}"
  next unless confirm
  c.update!(status: :disabled)
end

if confirm
  puts "已停用 #{contacts.count} 个"

  # 顺带检查：这些联系方式所属 KOL 是否因此变为「无法联系」
  kol_ids = contacts.map(&:kol_id).uniq
  affected = Kol.where(id: kol_ids).select { |k| !k.has_outreachable_contacts? && %w[pending contacting].include?(k.status.to_s) }
  puts "其中因此变为「无法联系」的 KOL（下次 KolScheduler.run 会自动标 unreachable）：#{affected.size} 个"
  affected.each { |k| puts "  KOL##{k.id} #{k.name} status=#{k.status}" }
else
  puts "以上为预览。确认后加 confirm 参数执行："
  puts "  bundle exec rails runner scripts/mark_dm_closed_contacts.rb --ids=#{ids.join(',')} confirm"
end
