# 临时脚本：探查「twitter 发了消息但对方还没回复」的联系方式，按发起账号分布统计。
# 只读，不改库。用于决定后续补查回复脚本用「固定 934」还是「last_outgoing_account」。
#
# 用法：
#   bundle exec rails runner scripts/probe_twitter_unreplied.rb

EXCLUDED_STATUSES = [
  Kol.statuses[:replied_unprocessed],
  Kol.statuses[:negotiating]
].freeze

# 初筛：排除「待回复 / 洽谈中」，且至少有一个 twitter 联系方式的 KOL
kol_ids = Kol.where.not(status: EXCLUDED_STATUSES)
             .joins(:kol_contacts)
             .where(kol_contacts: { platform: KolContact.platforms[:twitter] })
             .distinct.pluck(:id)

puts "符合初筛的 KOL 总数: #{kol_ids.size}"

# 发了消息但没回复的 twitter 联系方式，按「发起账号」分桶
by_account = Hash.new(0)
by_kol_status = Hash.new(0)
matched_contact_ids = []

KolContact.where(kol_id: kol_ids, platform: KolContact.platforms[:twitter])
          .includes(:kol).find_each do |c|
  has_sent = c.kol_messages.exists?(direction: KolMessage.directions[:outgoing],
                                    status: KolMessage.statuses[:sent_success])
  has_in = c.kol_messages.exists?(direction: KolMessage.directions[:incoming])
  next unless has_sent && !has_in

  matched_contact_ids << c.id
  acct = c.last_outgoing_account
  key = acct ? "账号##{acct.id}(#{acct.status})" : '无发起账号'
  by_account[key] += 1
  by_kol_status[c.kol.status] += 1
end

puts '=' * 60
puts "发了没回复的 twitter 联系方式：#{matched_contact_ids.size} 个"
puts '=' * 60
puts '—— 按发起账号分布 ——'
by_account.sort.each { |k, v| puts "#{k}: #{v}" }
puts "\n—— 按 KOL 状态分布 ——"
by_kol_status.sort.each { |k, v| puts "#{k}: #{v}" }
