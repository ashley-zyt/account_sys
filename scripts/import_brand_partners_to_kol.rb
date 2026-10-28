# 导入：CreatorDB 品牌合作伙伴 → KOL / KolContact
#
# 用法：
#   bundle exec rails runner scripts/import_brand_partners_to_kol.rb [brandId] [platform] [dry]
#   默认 brandId=binance.us, platform=youtube
#   加 dry 只预览映射、不落库
#
# 读取：tmp/creatordb/brand_contacts_<brandId>_<platform>.json
# 规则：
#   - owner 固定「杜维」，domain 固定「数字货币」（不存在则自动创建）
#   - notes 存该创作者整条 JSON，方便追溯
#   - 按 URL 域名识别联系方式平台；空 url 跳过
#   - messaging_enabled=false，status=reserved（未开始）
#   - 查重：联系方式 url 已存在则跳过；无联系方式时按 name 兜底去重

require 'json'
require 'uri'

OWNER = '杜维'
DOMAIN_NAME = '数字货币'

# ISO 3166-1 alpha-3 → 中文国家/地区名（覆盖当前数据里出现的 66 个；未命中则回退原代码）
COUNTRY_NAMES = {
  'BRA' => '巴西', 'USA' => '美国', 'ARE' => '阿联酋', 'IND' => '印度',
  'ARG' => '阿根廷', 'TUR' => '土耳其', 'TWN' => '中国台湾', 'PAK' => '巴基斯坦',
  'EGY' => '埃及', 'ESP' => '西班牙', 'KOR' => '韩国', 'UKR' => '乌克兰',
  'IDN' => '印度尼西亚', 'BGD' => '孟加拉国', 'VNM' => '越南', 'RUS' => '俄罗斯',
  'LKA' => '斯里兰卡', 'HKG' => '中国香港', 'GBR' => '英国', 'COL' => '哥伦比亚',
  'POL' => '波兰', 'FRA' => '法国', 'THA' => '泰国', 'ITA' => '意大利',
  'MEX' => '墨西哥', 'ROU' => '罗马尼亚', 'KHM' => '柬埔寨', 'MAR' => '摩洛哥',
  'DEU' => '德国', 'SGP' => '新加坡', 'KAZ' => '哈萨克斯坦', 'DOM' => '多米尼加',
  'CAN' => '加拿大', 'PHL' => '菲律宾', 'CHL' => '智利', 'HUN' => '匈牙利',
  'SRB' => '塞尔维亚', 'SWE' => '瑞典', 'MYS' => '马来西亚', 'JOR' => '约旦',
  'EST' => '爱沙尼亚', 'GEO' => '格鲁吉亚', 'SAU' => '沙特阿拉伯', 'DZA' => '阿尔及利亚',
  'CHE' => '瑞士', 'ZAF' => '南非', 'MLT' => '马耳他', 'VGB' => '英属维尔京群岛',
  'BEL' => '比利时', 'AUT' => '奥地利', 'GRC' => '希腊', 'KWT' => '科威特',
  'SVK' => '斯洛伐克', 'HND' => '洪都拉斯', 'PAN' => '巴拿马', 'HRV' => '克罗地亚',
  'JPN' => '日本', 'FIN' => '芬兰', 'CZE' => '捷克', 'ISR' => '以色列',
  'PRT' => '葡萄牙', 'SEN' => '塞内加尔', 'NGA' => '尼日利亚', 'SLV' => '萨尔瓦多',
}.freeze

def country_name(code)
  COUNTRY_NAMES.fetch(code.to_s, code.to_s)
end

def sanitize(str)
  str.to_s.gsub(/[^a-zA-Z0-9._-]/, '_')
end

# 清理 CreatorDB 返回的 URL：去掉反引号、不可见/双向控制字符（如 \u2069）
def clean_url(url)
  url.to_s
     .delete('`')
     .gsub(/[\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]/, '')
     .strip
end

# 用 URL 域名识别平台（title 不规范，不能依赖 title）
def platform_from_url(url)
  u = clean_url(url)
  return nil if u.blank?
  return 'email' if u.downcase.start_with?('mailto:')

  # 无协议时补 https://（如 "tiktok.com/@xxx"），否则解析不出 host
  u = "https://#{u}" unless u.match?(/\A[a-z][a-z0-9+.-]*:\/\//i)

  host = begin
    URI.parse(u).host.to_s.downcase.sub(/\Awww\./, '')
  rescue URI::InvalidURIError
    nil
  end
  return nil if host.blank?

  return 'telegram'  if host == 't.me' || host.end_with?('.t.me') || host == 'telegram.me' || host.end_with?('telegram.org')
  return 'twitter'   if host == 'x.com' || host.end_with?('.x.com') || host == 'twitter.com' || host.end_with?('.twitter.com')
  return 'instagram' if host == 'instagram.com' || host.end_with?('.instagram.com')
  return 'facebook'  if host == 'facebook.com' || host.end_with?('.facebook.com') || host == 'fb.com'
  return 'tiktok'    if host == 'tiktok.com' || host.end_with?('.tiktok.com')
  return 'youtube'   if host == 'youtube.com' || host.end_with?('.youtube.com') || host == 'youtu.be'
  return 'linkedin'  if host == 'linkedin.com' || host.end_with?('.linkedin.com')
  return 'whatsapp'  if host == 'whatsapp.com' || host.end_with?('.whatsapp.com') || host == 'wa.me' || host.end_with?('.wa.me')
  return 'discord'   if host == 'discord.gg' || host.end_with?('.discord.gg') || host == 'discord.com' || host.end_with?('.discord.com')
  return 'twitch'    if host == 'twitch.tv' || host.end_with?('.twitch.tv') || host == 'twitch.com'

  'other'
end

def build_contacts(item)
  contacts = []
  (item.dig('profile', 'data', 'otherLinks') || []).each do |l|
    url = clean_url(l['url'])
    next if url.blank?
    url = url[0, 255]  # kol_contacts.url 是 string(255)，超长截断避免入库报错

    platform = platform_from_url(url)
    next if platform.nil?
    # 未识别平台时，用 title 进一步细分官网（website）
    if platform == 'other'
      title = (l['title'] || '').to_s.downcase
      platform = 'website' if title.include?('website') || title.include?('official') || title.include?('homepage') || title.include?('官网')
    end
    contacts << { platform: platform, url: url }
  end

  # 邮箱（如果抓取时带了 email，才会有 contact.emails）
  (item.dig('contact', 'data', 'emails') || []).each do |email|
    e = email.to_s.strip
    next if e.blank?
    contacts << { platform: 'email', url: e }
  end
  contacts
end

# 一次性修复：把之前已导入、仍存国家代码（如 USA）的 KOL 的 country 改成中文
def fix_countries
  domain = Domain.find_by(name: DOMAIN_NAME)
  scope = domain ? Kol.where(owner: OWNER, domain_id: domain.id) : Kol.none

  updated = 0
  scope.find_each do |kol|
    code = kol.country.to_s.strip
    name = COUNTRY_NAMES[code]
    next if name.nil? || name == code

    kol.update_columns(country: name, updated_at: Time.current)
    updated += 1
    puts "更新: #{kol.name}: #{code} -> #{name}"
  end
  puts "\n完成：更新国家字段 #{updated} 条"
end

def run
  if ARGV[0] == 'fix_countries'
    fix_countries
    return
  end

  brand_id = ARGV[0] || 'binance.us'
  platform = ARGV[1] || 'youtube'
  dry_run  = ARGV.include?('dry')

  path = Rails.root.join('tmp', 'creatordb', "brand_contacts_#{sanitize(brand_id)}_#{platform}.json")
  unless File.exist?(path)
    puts "[错误] 找不到文件：#{path}"
    exit 1
  end

  domain = Domain.find_or_create_by_name(DOMAIN_NAME)
  data = JSON.parse(File.read(path))

  created = 0
  skipped = 0
  failed  = 0

  data.each do |item|
    name = (item['displayName'] || '').to_s.strip[0, 255]
    if name.blank?
      skipped += 1
      next
    end

    contacts = build_contacts(item)
    if contacts.empty?
      puts "跳过(无联系方式): #{name}"
      skipped += 1
      next
    end

    urls = contacts.map { |c| c[:url] }

    # 查重：按联系方式 url
    dup = Kol.find_duplicate(contact_urls: urls)
    if dup
      puts "跳过(url重复): #{name} -> #{dup[:value]}"
      skipped += 1
      next
    end

    if dry_run
      puts "[dry] #{name} | 联系方式 #{contacts.size} 条 | " + contacts.map { |c| c[:platform] }.join(',')
      next
    end

    kol = Kol.new(
      name:       name,
      owner:      OWNER,
      domain_id:  domain.id,
      country:    country_name(item['country']),
      follower_tier: item['followers'].to_s,
      notes:      JSON.pretty_generate(item),
      status:     :reserved,
      kol_contacts_attributes: contacts.map { |c| { platform: c[:platform], url: c[:url] } }
    )

    if kol.save
      created += 1
      puts "导入: #{name}（#{contacts.size} 条）"
    else
      failed += 1
      puts "失败: #{name} -> #{kol.errors.full_messages.join('; ')}"
    end
  end

  puts "\n完成：成功 #{created}，跳过 #{skipped}，失败 #{failed}#{dry_run ? '（dry 预览，未落库）' : ''}"
end

run
