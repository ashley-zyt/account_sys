# 临时脚本：KOL 触达模块数据治理 —— 诊断现状分布（只读，不改库）。
#
# 目标：摸清当前 KOL / 联系方式的状态分布，为「归一调整」提供依据。
# 重点统计：
#   1. KOL 状态分布
#   2. twitter 联系方式的 url 合法性分布（纯 @username / 完整链接可提取 / 非法）
#   3. twitter 联系方式状态 × 是否可触达 分布
#   4. 卡在「联系中」的 KOL / 联系方式数量
#   5. 每个 KOL 是否有「合法可触达 twitter 联系方式」
#
# 用法：
#   bundle exec rails runner scripts/diagnose_kol_governance.rb

# 判断 twitter url 是否合法（能提取出 @username）
def twitter_username(url)
  u = url.to_s.strip
  return u.sub(/\A@/, '') if u.match?(/\A@?[A-Za-z0-9_]{1,15}\z/)
  if u =~ %r{https?://(?:www\.)?(?:x|twitter)\.com/([A-Za-z0-9_]{1,15})}
    return Regexp.last_match(1)
  end
  nil
end

puts '=' * 60
puts 'KOL 状态分布'
puts '=' * 60
Kol.group(:status).count.sort.each { |s, n| puts "  #{s}: #{n}" }

puts "\n" + '=' * 60
puts 'KolContact 状态 × 平台 分布'
puts '=' * 60
KolContact.group(:platform, :status).count.sort.each do |(p, s), n|
  puts "  platform=#{p} status=#{s}: #{n}"
end

puts "\n" + '=' * 60
puts 'twitter 联系方式的 url 合法性分布'
puts '=' * 60
tw = KolContact.where(platform: KolContact.platforms[:twitter])
tw_urls = tw.pluck(:url)
pure = tw_urls.count { |u| u.to_s.match?(/\A@?[A-Za-z0-9_]{1,15}\z/) }
extractable = tw_urls.count { |u| !u.to_s.match?(/\A@?[A-Za-z0-9_]{1,15}\z/) && twitter_username(u).present? }
invalid = tw_urls.size - pure - extractable
puts "  纯 @username: #{pure}"
puts "  完整链接可提取: #{extractable}"
puts "  非法（无法提取）: #{invalid}"

puts "\n" + '=' * 60
puts 'twitter 联系方式：状态 × 可触达（url合法）分布'
puts '=' * 60
tw.find_each do |c|
  # 略，下面按汇总统计
end
# 汇总统计
summary = Hash.new(0)
tw.each do |c|
  url_ok = twitter_username(c.url).present?
  key = "status=#{c.status} url_ok=#{url_ok} messaging_enabled=#{c.messaging_enabled}"
  summary[key] += 1
end
summary.sort.each { |k, n| puts "  #{k}: #{n}" }

puts "\n" + '=' * 60
puts '卡在「联系中」的 KOL 数量'
puts '=' * 60
contacting_kol = Kol.where(status: Kol.statuses[:contacting]).count
contacting_contact = KolContact.where(status: KolContact.statuses[:contacting]).count
puts "  KOL 联系中: #{contacting_kol}"
puts "  联系方式联系中: #{contacting_contact}"

puts "\n" + '=' * 60
puts '每个 KOL 是否有「合法可触达 twitter 联系方式」'
puts '=' * 60
# 合法可触达 = twitter + active + messaging_enabled + url 合法
legal_tw_ids = tw.where(status: KolContact.statuses[:active], messaging_enabled: true)
                 .select { |c| twitter_username(c.url).present? }
                 .map(&:kol_id).uniq

has_legal = legal_tw_ids.size
total_kol = Kol.count
puts "  有合法可触达 twitter 的 KOL: #{has_legal} / #{total_kol}"
puts "  没有的: #{total_kol - has_legal}"

# 各状态下有多少「有合法联系方式」
puts "\n  按 KOL 状态细分（有合法 twitter / 无）："
Kol.group(:status).count.sort.each do |s, n|
  ids = Kol.where(status: s).pluck(:id)
  with = (ids & legal_tw_ids).size
  puts "    #{s}: 有=#{with} 无=#{n - with}"
end
