# 临时脚本：把「未开始（reserved）」且含有效 twitter 联系方式的 KOL 改为「待联系（pending）」。
#
# 「有效 twitter 联系方式」口径（与归一脚本一致）：
#   platform=twitter + status=active + messaging_enabled=true + url 能提取出 @username
#
# 变量完整性门槛：pending_queue 只处理 variables_incomplete=false 的 KOL。
#   变量完整的才改 pending；变量不完整的保持 reserved 并列出，避免「改了 pending 却永远不被处理」。
#
# 用法（先预览，再执行）：
#   预览： bundle exec rails runner scripts/activate_reserved_kols.rb
#   执行： EXEC=1 bundle exec rails runner scripts/activate_reserved_kols.rb

PHASE_EXEC = ENV['EXEC'] == '1'

# 判断 twitter url 是否合法（能提取出 @username）
def twitter_username(url)
  u = url.to_s.strip
  return u.sub(/\A@/, '') if u.match?(/\A@?[A-Za-z0-9_]{1,15}\z/)
  if u =~ %r{(?:https?://)?(?:www\.)?(?:x|twitter)\.com/([A-Za-z0-9_]{1,15})}i
    return Regexp.last_match(1)
  end
  nil
end

reserved = Kol.where(status: Kol.statuses[:reserved]).order(:id)

to_activate = []   # 变量完整 + 有有效 twitter → 改 pending
missing_vars = []  # 有有效 twitter 但变量不完整 → 保持 reserved

reserved.find_each do |kol|
  has_valid_twitter = kol.kol_contacts
                          .where(platform: KolContact.platforms[:twitter],
                                 status: KolContact.statuses[:active],
                                 messaging_enabled: true)
                          .any? { |c| twitter_username(c.url).present? }
  next unless has_valid_twitter

  if kol.variables_complete?
    to_activate << kol
  else
    missing = kol.missing_entry_variables
    missing_vars << [kol.id, missing]
  end
end

puts '=' * 60
puts "reserved 状态 KOL 总数: #{reserved.count}"
puts '=' * 60
puts "  有有效 twitter + 变量完整（将改待联系）: #{to_activate.size}"
puts "  有有效 twitter 但变量不完整（保持未开始）: #{missing_vars.size}"

if missing_vars.any?
  puts "\n  —— 变量不完整、需补全后再激活的 KOL ——"
  missing_vars.first(30).each { |kid, miss| puts "    KOL##{kid}: 缺 #{miss.join('、')}" }
  puts "    （共 #{missing_vars.size} 个）" if missing_vars.size > 30
end

exit unless PHASE_EXEC

done = 0
to_activate.each do |kol|
  kol.update!(status: :pending, next_action_at: nil)
  done += 1
  puts "[待联系] KOL##{kol.id} #{kol.name}"
rescue => e
  Rails.logger.error "[ActivateReservedKols] KOL##{kol&.id} 异常: #{e.message}"
end

puts '=' * 60
puts "完成：已把 #{done} 个 KOL 从「未开始」改为「待联系」"
