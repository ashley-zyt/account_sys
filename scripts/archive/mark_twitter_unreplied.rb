# 临时脚本：把「发消息成功过、但对方没回复」的 twitter 联系方式直接置为「未回复」。
# 不查回复，一次性把历史遗留的「已发未回」KOL 结算掉，以后不再触发。
#
# 范围：
#   - twitter 联系方式，存在「发送成功（sent_success）」的 outgoing 消息，且无任何 incoming 回复
#   - 排除 KOL 状态 = 待回复（replied_unprocessed）/ 洽谈中（negotiating），这两类已有回复或人工跟进，不动
#
# 动作：
#   - 联系方式 → 未回复（unresponsive），清监测字段
#   - KOL → 未回复（unresponsive），清 next_action_at（以后不再自动触达）
#
# 用法：
#   预览： bundle exec rails runner scripts/mark_twitter_unreplied.rb
#   执行： EXEC=1 bundle exec rails runner scripts/mark_twitter_unreplied.rb
#   分批： IDS=1,2,3 bundle exec rails runner scripts/mark_twitter_unreplied.rb

PHASE_EXEC = ENV['EXEC'] == '1'

EXCLUDED_KOL_STATUSES = [
  Kol.statuses[:replied_unprocessed],
  Kol.statuses[:negotiating]
].freeze

raw_ids = ENV['IDS'].to_s
BATCH_IDS = raw_ids.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

# 收集目标：twitter 联系方式发了成功、无 incoming 回复、KOL 不在排除状态
targets = []
KolContact.where(platform: KolContact.platforms[:twitter])
          .includes(:kol).find_each do |c|
  next if BATCH_IDS.any? && !BATCH_IDS.include?(c.kol_id)
  next if EXCLUDED_KOL_STATUSES.include?(c.kol.status)

  has_sent = c.kol_messages.exists?(direction: KolMessage.directions[:outgoing],
                                    status: KolMessage.statuses[:sent_success])
  has_in = c.kol_messages.exists?(direction: KolMessage.directions[:incoming])
  targets << c if has_sent && !has_in
end

puts "目标 twitter 联系方式（发了成功、无回复）：#{targets.size} 个"
puts '-' * 60

# 按 KOL 状态分布展示
by_status = targets.group_by { |c| c.kol.status }
by_status.sort.each { |k, v| puts "  KOL 状态 #{k}: #{v.size} 个" }

exit unless PHASE_EXEC

done = skipped = errors = 0
targets.each do |contact|
  kol = contact.kol
  # 已被回调转「已回复」的跳过（双保险）
  if contact.kol_messages.exists?(direction: KolMessage.directions[:incoming])
    skipped += 1
    puts "[跳过] contact##{contact.id}（KOL##{kol.id}）已有 incoming 回复"
    next
  end

  contact.update!(status: :unresponsive, monitor_until: nil, next_poll_at: nil)
  if %w[pending contacting unreachable unresponsive].include?(kol.status.to_s)
    kol.update!(status: :unresponsive, next_action_at: nil)
  end
  done += 1
  puts "[未回复] KOL##{kol.id} #{kol.name}（contact##{contact.id}）"
rescue => e
  errors += 1
  Rails.logger.error "[MarkTwitterUnreplied] contact##{contact&.id} 异常: #{e.message}"
end

puts '=' * 60
puts "完成：置未回复 #{done}，跳过 #{skipped}，异常 #{errors}"
