# 临时脚本：复活「未回复 / 无法联系」的 KOL —— 仅当存在「从未联系过的新渠道」时。
#
# 背景：KOL 因「所有已联系渠道都未回复」被标 unresponsive，或「无可私信渠道」被标 unreachable。
#   之后若启用了新渠道（如 instagram 重新打开、新增了联系方式），这些 KOL 不应永远卡死，
#   需要人工触发本脚本把「有新渠道可试」的 KOL 复活回待联系。
#
# 复活判定（严格，避免死循环）：
#   KOL 状态 ∈ [unresponsive, unreachable]，且存在 outreach_usable? 的联系方式
#   （= status active「未联系」+ messaging_enabled + 平台已启用 + 账号池支持）。
#   已联系过但未回复的渠道 status ≠ active，不会触发复活，因此不会反复打扰。
#
# 额外校验：变量完整才复活（否则进不了 pending_queue，白白改状态）。
#
# 用法（先预览，再执行）：
#   预览： bundle exec rails runner scripts/revive_kols.rb
#   执行： EXEC=1 bundle exec rails runner scripts/revive_kols.rb
#   分批： IDS=1,2,3 bundle exec rails runner scripts/revive_kols.rb

PHASE_EXEC = ENV['EXEC'] == '1'

raw_ids = ENV['IDS'].to_s
BATCH_IDS = raw_ids.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

TARGET_STATUSES = [Kol.statuses[:unresponsive], Kol.statuses[:unreachable]].freeze

kols = Kol.where(status: TARGET_STATUSES)
kols = kols.where(id: BATCH_IDS) if BATCH_IDS.any?
kols = kols.order(:id)

revivable = []   # 可复活（有新渠道 + 变量完整）
no_channel = []  # 无新渠道（保持）
no_vars = []     # 有新渠道但变量不完整（保持）

kols.find_each do |kol|
  if kol.has_outreachable_contacts?
    if kol.variables_complete?
      revivable << kol
    else
      no_vars << kol
    end
  else
    no_channel << kol
  end
end

puts '=' * 60
puts "目标 KOL 总数（未回复/无法联系）: #{kols.count}"
puts '=' * 60
puts "  可复活（有新渠道 + 变量完整）: #{revivable.size}"
puts "  有新渠道但变量不完整（保持）: #{no_vars.size}"
puts "  无新渠道（保持）: #{no_channel.size}"

if revivable.any?
  puts "\n可复活的 KOL id：#{revivable.map(&:id).join(', ')}"
end
if no_vars.any?
  puts "\n变量不完整的 KOL id：#{no_vars.map(&:id).join(', ')}"
end

exit unless PHASE_EXEC

done = 0
revivable.each do |kol|
  kol.update!(status: :pending, next_action_at: nil)
  done += 1
  puts "[复活] KOL##{kol.id} #{kol.name}"
rescue => e
  Rails.logger.error "[ReviveKols] KOL##{kol&.id} 异常: #{e.message}"
end

puts '=' * 60
puts "完成：复活 #{done} 个 KOL 回待联系"
