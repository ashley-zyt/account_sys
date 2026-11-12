# 一次性数据治理脚本：把 KOL 触达模块的存量脏数据按最终规则一次性归位。
#
# 最终规则（与代码阶段一/二/三对齐）：
#   通道：twitter → X API（固定 934）；instagram → 浏览器（当前停用）；其它平台 → 不可私信
#   合法可触达 = twitter + status=active + messaging_enabled + url 能提取出 @username
#
# 第一步：联系方式归一
#   1. twitter + url 合法 + status=contacting（历史卡死）→ 回退 active
#   2. twitter + url 合法 + status≠disabled → messaging_enabled=true
#   3. twitter + url 不合法 → status=disabled（数据质量问题，需人工修 url）
#   4. twitter + status=disabled（历史停用）→ 保持不动
#   5. 非 twitter（instagram 等）→ messaging_enabled=false
#
# 第二步：KOL 状态归一（排除人工终态 replied_unprocessed/negotiating/cooperating/failed/in_conversation
#                          和 reserved「未开始」、unresponsive「未回复」）
#   有合法可触达 twitter → pending（待联系）
#   无 → unreachable（无法联系）
#
# 用法（先预览，再执行）：
#   预览： bundle exec rails runner scripts/normalize_kol_governance.rb
#   执行： EXEC=1 bundle exec rails runner scripts/normalize_kol_governance.rb

PHASE_EXEC = ENV['EXEC'] == '1'

# 判断 twitter url 是否合法（能提取出 @username）
def twitter_username(url)
  u = url.to_s.strip
  return u.sub(/\A@/, '') if u.match?(/\A@?[A-Za-z0-9_]{1,15}\z/)
  if u =~ %r{https?://(?:www\.)?(?:x|twitter)\.com/([A-Za-z0-9_]{1,15})}
    return Regexp.last_match(1)
  end
  nil
end

# KOL 状态中「人工终态 / 系统终态」，归一脚本不碰
KOL_SKIP_STATUSES = [
  Kol.statuses[:reserved],            # 未开始（人工决定）
  Kol.statuses[:replied_unprocessed], # 待回复
  Kol.statuses[:negotiating],         # 人工洽谈中
  Kol.statuses[:cooperating],         # 已合作
  Kol.statuses[:failed],              # 已拒绝
  Kol.statuses[:unresponsive],        # 未回复（终态，复活走 revive_kols.rb）
  Kol.statuses[:in_conversation]      # 跟进中
].freeze

# ============ 预览统计 ============
tw_contacts = KolContact.where(platform: KolContact.platforms[:twitter])

contact_stats = {
  url_ok: 0,           # url 合法
  url_bad: 0,          # url 不合法
  contacting_stuck: 0, # 联系中卡死（回退 active）
  already_disabled: 0  # 历史停用（保持）
}
bad_url_samples = []

tw_contacts.find_each do |c|
  if twitter_username(c.url).present?
    if c.contacting?
      contact_stats[:contacting_stuck] += 1
    elsif c.disabled?
      contact_stats[:already_disabled] += 1
    else
      contact_stats[:url_ok] += 1
    end
  else
    contact_stats[:url_bad] += 1
    bad_url_samples << [c.id, c.kol_id, c.url.to_s.truncate(40)]
  end
end

kol_total = Kol.count
kol_will_process = Kol.where.not(status: KOL_SKIP_STATUSES).count

puts '=' * 60
puts '第一步：联系方式归一预览'
puts '=' * 60
puts "  twitter 联系方式总数: #{tw_contacts.count}"
puts "    url 合法、正常: #{contact_stats[:url_ok]}"
puts "    url 合法、联系中卡死（将回退 active）: #{contact_stats[:contacting_stuck]}"
puts "    url 不合法（将停用）: #{contact_stats[:url_bad]}"
puts "    历史停用（保持）: #{contact_stats[:already_disabled]}"
if bad_url_samples.any?
  puts "\n  —— url 不合法的 twitter 联系方式（前 20 条）——"
  bad_url_samples.first(20).each { |cid, kid, url| puts "    contact##{cid}（KOL##{kid}）: #{url}" }
  puts "    （共 #{bad_url_samples.size} 条）" if bad_url_samples.size > 20
end

puts "\n" + '=' * 60
puts '第二步：KOL 状态归一预览'
puts '=' * 60
puts "  KOL 总数: #{kol_total}"
puts "  将处理（排除人工终态/未回复/未开始）: #{kol_will_process}"
puts "  跳过（reserved/待回复/洽谈中/已合作/已拒绝/未回复/跟进中）: #{kol_total - kol_will_process}"

exit unless PHASE_EXEC

# ============ 执行 ============
contact_done = 0
tw_contacts.find_each do |c|
  if twitter_username(c.url).present?
    if c.contacting?
      c.update!(status: :active, monitor_until: nil, next_poll_at: nil)
    elsif !c.disabled?
      c.update!(messaging_enabled: true)
    end
  else
    c.update!(status: :disabled, messaging_enabled: false)
  end
  contact_done += 1
rescue => e
  Rails.logger.error "[NormalizeKolGovernance] contact##{c&.id} 异常: #{e.message}"
end

# 非 twitter 联系方式统一关私信
KolContact.where.not(platform: KolContact.platforms[:twitter])
          .update_all(messaging_enabled: false, updated_at: Time.current)

# KOL 状态归一
kol_done = { pending: 0, unreachable: 0 }
Kol.where.not(status: KOL_SKIP_STATUSES).find_each do |kol|
  if kol.has_outreachable_contacts?
    kol.update!(status: :pending, next_action_at: nil)
    kol_done[:pending] += 1
  else
    kol.update!(status: :unreachable, next_action_at: nil)
    kol_done[:unreachable] += 1
  end
rescue => e
  Rails.logger.error "[NormalizeKolGovernance] KOL##{kol&.id} 异常: #{e.message}"
end

puts '=' * 60
puts '执行完成'
puts "  联系方式已归一: #{contact_done} 个"
puts "  KOL 归为待联系: #{kol_done[:pending]}"
puts "  KOL 归为无法联系: #{kol_done[:unreachable]}"
