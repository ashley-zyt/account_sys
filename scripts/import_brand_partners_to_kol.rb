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

def run
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
    name = (item['displayName'] || '').to_s.strip
    if name.blank?
      skipped += 1
      next
    end

    contacts = build_contacts(item)
    urls = contacts.map { |c| c[:url] }

    # 查重：优先按联系方式 url；无联系方式时按 name 兜底
    if urls.any?
      dup = Kol.find_duplicate(contact_urls: urls)
      if dup
        puts "跳过(url重复): #{name} -> #{dup[:value]}"
        skipped += 1
        next
      end
    elsif Kol.exists?(name: name)
      puts "跳过(同名): #{name}"
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
      country:    item['country'],
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
