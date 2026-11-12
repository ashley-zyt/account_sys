# 临时脚本：批量规范 KOL 联系方式，只保留 twitter / instagram 为可私信，并对待联系 KOL 重新入队。
#
# 规则：
#   1. 只把 twitter 和 instagram 设为「可私信」（messaging_enabled=true），其余平台设为 false
#   2. twitter 第一优先级（priority=0），instagram 第二优先级（priority=1）
#   3. 没有 twitter 也没有 instagram 的 KOL → 保持不变（跳过）
#   4. twitter 走 X API（通道由平台决定），url 规范化为 @username（自动从完整链接提取）；
#      提取不出的标记出来，不处理该 KOL
#   5. 满足条件（有可用的 twitter 或 instagram）→ KOL 改「待联系」（pending）
#
# 用法（先预览，再执行）：
#   预览： bundle exec rails runner scripts/normalize_kol_outreach.rb
#   执行： EXEC=1 bundle exec rails runner scripts/normalize_kol_outreach.rb
#   分批： IDS=1,2,3 bundle exec rails runner scripts/normalize_kol_outreach.rb

PHASE_EXEC = ENV['EXEC'] == '1'

raw_ids = ENV['IDS'].to_s
BATCH_IDS = raw_ids.split(/[,\s]+/).map(&:to_i).reject(&:zero?).uniq

# 把 twitter url 规范化为 @username；返回 [规范化后的 url 或 nil, 错误信息或 nil]
def normalize_twitter_url(url)
  u = url.to_s.strip
  return [nil, '空链接'] if u.blank?

  # 已是纯 @username 或 username
  if u.match?(/\A@?[A-Za-z0-9_]{1,15}\z/)
    return ["@#{u.sub(/\A@/, '')}", nil]
  end

  # 完整链接：主页 https://x.com/name 或推文 https://x.com/name/status/xxx
  if u =~ %r{https?://(?:www\.)?(?:x|twitter)\.com/([A-Za-z0-9_]{1,15})}
    return ["@#{Regexp.last_match(1)}", nil]
  end

  [nil, "无法识别为 X username：#{u.truncate(40)}"]
end

kols = Kol.all
kols = kols.where(id: BATCH_IDS) if BATCH_IDS.any?
kols = kols.order(:id)

stats = {
  skipped_no_tw_ig: 0,    # 无 twitter/instagram，保持不变
  will_process: 0,        # 将处理
  twitter_ok: 0,          # twitter 规范化成功
  twitter_bad: 0,         # twitter 规范化失败（整个 KOL 不处理）
  to_pending: 0           # 将改待联系
}
tw_bad_samples = []

# 预览：先算一遍分类
kols.find_each do |kol|
  contacts = kol.kol_contacts.to_a
  tw = contacts.select { |c| c.platform.to_s == 'twitter' }
  ig = contacts.select { |c| c.platform.to_s == 'instagram' }

  if tw.empty? && ig.empty?
    stats[:skipped_no_tw_ig] += 1
    next
  end

  # 有 twitter 就先校验链接
  if tw.any?
    all_ok = tw.all? { |c| normalize_twitter_url(c.url)[0].present? }
    unless all_ok
      stats[:twitter_bad] += 1
      tw_bad_samples << [kol.id, tw.map { |c| c.url.to_s.truncate(30) }.join(' | ')]
      next
    end
    stats[:twitter_ok] += tw.size
  end

  stats[:will_process] += 1
  stats[:to_pending] += 1
end

puts '=' * 60
puts "KOL 总数: #{kols.count}"
puts '=' * 60
puts "  无 twitter/instagram（保持不变）: #{stats[:skipped_no_tw_ig]}"
puts "  twitter 链接规范化失败（跳过）: #{stats[:twitter_bad]}"
puts "  将处理并改待联系: #{stats[:to_pending]}"
puts "  其中 twitter 联系方式规范化成功: #{stats[:twitter_ok]} 个"

if tw_bad_samples.any?
  puts "\n  —— twitter 链接无法识别的 KOL（需人工改 url）——"
  tw_bad_samples.first(20).each { |kid, urls| puts "    KOL##{kid}: #{urls}" }
  puts "    （共 #{tw_bad_samples.size} 个）" if tw_bad_samples.size > 20
end

exit unless PHASE_EXEC

processed = 0
kols.find_each do |kol|
  contacts = kol.kol_contacts.to_a
  tw = contacts.select { |c| c.platform.to_s == 'twitter' }
  ig = contacts.select { |c| c.platform.to_s == 'instagram' }

  next if tw.empty? && ig.empty?

  # twitter 链接校验（不满足则整个 KOL 跳过）
  next if tw.any? && tw.any? { |c| normalize_twitter_url(c.url)[0].nil? }

  # 1) 只有 twitter/instagram 可私信，其余关闭
  contacts.each do |c|
    enable = c.platform.to_s == 'twitter' || c.platform.to_s == 'instagram'
    c.update!(messaging_enabled: enable)
  end

  # 2) 优先级：twitter=0 第一，instagram=1 第二；通道由平台决定（twitter→X API），无需写 outreach_channel
  tw.each do |c|
    new_url, = normalize_twitter_url(c.url)
    c.update!(priority: 0, url: new_url, status: :active)
  end
  ig.each { |c| c.update!(priority: 1, status: :active) }

  # 3) KOL 改待联系
  kol.update!(status: :pending, next_action_at: nil)
  processed += 1
  puts "[待联系] KOL##{kol.id} #{kol.name}（twitter=#{tw.size} instagram=#{ig.size}）"
rescue => e
  Rails.logger.error "[NormalizeKolOutreach] KOL##{kol&.id} 异常: #{e.message}"
end

puts '=' * 60
puts "完成：已处理并改待联系 #{processed} 个 KOL"
