# 临时脚本：统计「无法联系」KOL 的分布，回答「是不是都发了消息还没确认回复」。
# 按每个 KOL 的私信往来情况分桶（只看方向 incoming / outgoing + 状态），只读不改库。
#
# 用法：
#   bundle exec rails runner scripts/classify_unreachable_kols.rb
#   可选 IDS=1,2,3 只看指定 KOL

raw_ids = ENV['IDS'].to_s
BATCH_IDS = raw_ids.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

kols = Kol.unreachable
kols = kols.where(id: BATCH_IDS) if BATCH_IDS.any?

# 桶名 -> 计数
buckets = Hash.new(0)
# 每桶样例（最多存 20 个 KOL id，便于定位）
samples = Hash.new { |h, k| h[k] = [] }

def bucket_of(kol)
  contacts = kol.kol_contacts.to_a
  return 'D_无联系方式' if contacts.empty?

  has_incoming = contacts.any? { |c| c.kol_messages.exists?(direction: :incoming) }
  return 'E_已有回复却仍无法联系' if has_incoming

  has_sent_success = contacts.any? { |c| c.kol_messages.exists?(direction: :outgoing, status: :sent_success) }
  return 'B_已发出私信待确认回复' if has_sent_success

  has_any_outgoing = contacts.any? { |c| c.kol_messages.exists?(direction: :outgoing) }
  return 'C_有下发但无成功(发失败/超时/排队)' if has_any_outgoing

  'A_从未发过私信'
end

kols.find_each do |kol|
  key = bucket_of(kol)
  buckets[key] += 1
  samples[key] << kol.id if samples[key].size < 20
end

puts '=' * 60
puts "「无法联系」KOL 分布（共 #{kols.count} 个）"
puts '=' * 60
buckets.sort.each do |key, count|
  puts "\n#{key}: #{count}"
  puts "  样例 KOL id: #{samples[key].join(', ')}" if samples[key].any?
end
puts "\n说明：B=发了私信还没确认回复；E=其实已有回复但仍标无法联系；A=从没发过消息；C=发过但失败/超时/未成功；D=无联系方式"
