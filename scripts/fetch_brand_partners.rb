# 按品牌获取「合作伙伴（被赞助创作者）」及其联系方式
#
# 用法：
#   bundle exec rails runner scripts/fetch_brand_partners.rb search [关键词]         # 搜索品牌（默认 binance）
#   bundle exec rails runner scripts/fetch_brand_partners.rb <brandId> [platform]    # 列出合作伙伴并拉联系方式
#   bundle exec rails runner scripts/fetch_brand_partners.rb binance.us youtube email refresh  # 额外拉真实邮箱 + 强制刷新
#
# 环境变量：CREATORDB_API_KEY
# 缓存目录：tmp/creatordb/
#   brand_search.json            品牌搜索结果
#   brand_creators_<brand>.json  品牌赞助的创作者列表
#   brand_contacts_<brand>.json  创作者 profile(含社交链接/Telegram) + 邮箱
#
# 说明：
#   - /sponsor/creators 返回每个创作者的 creatorId（YouTube 即 channelId）
#   - 联系方式默认取 profile（含 otherLinks 里的 Telegram，2 积分/人）
#   - 加 email 参数时，对 hasEmail 为 true 的创作者再调 /youtube/contact 取真实邮箱（15 积分/人，仅在有邮箱时计费）

require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

API_KEY  = ENV['CREATORDB_API_KEY']
BASE_URL = 'https://apiv3.creatordb.app'
CACHE_DIR = File.join(Rails.root, 'tmp', 'creatordb')
BRAND_SEARCH_CACHE = File.join(CACHE_DIR, 'brand_search.json')

def http_request(klass, path, body = nil)
  uri = URI("#{BASE_URL}#{path}")
  req = klass.new(uri)
  req['Content-Type'] = 'application/json'
  req['api-key'] = API_KEY
  req.body = body.to_json if body

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 30
  http.read_timeout = 90

  resp = http.request(req)
  JSON.parse(resp.body)
rescue => e
  { 'error' => e.message }
end

def api_get(path, params = {})
  qs = params.any? ? "?#{URI.encode_www_form(params)}" : ''
  http_request(Net::HTTP::Get, "#{path}#{qs}")
end

def api_post(path, body = {})
  http_request(Net::HTTP::Post, path, body)
end

def sanitize(str)
  str.to_s.gsub(/[^a-zA-Z0-9._-]/, '_')
end

# 搜索品牌（名称模糊匹配），返回 data.results 数组
def search_brands(keyword)
  api_post('/sponsor/search', {
    'filters' => [
      { 'filterName' => 'name', 'op' => '=', 'value' => keyword, 'isFuzzySearch' => true }
    ],
    'pageSize' => 50,
    'offset'   => 0,
    'sortBy'   => 'name',
    'desc'     => false
  })
end

# 分页拉取某品牌在某平台赞助的创作者，返回数组
def list_sponsored_creators(brand_id, platform)
  all = []
  offset = 0
  loop do
    r = api_get('/sponsor/creators', {
      'brandId'  => brand_id,
      'platform' => platform,
      'pageSize' => 100,
      'offset'   => offset,
      'sortBy'   => 'followers',
      'desc'     => 'true'
    })
    break if r['error']

    data = r['data'] || {}
    batch = data['creators'] || []
    all.concat(batch)
    total = data['totalResults'].to_i
    offset += batch.size
    break if batch.empty? || offset >= total || offset >= 1000 # 安全上限 1000 人
  end
  all
end

def run_search(keyword)
  puts "搜索品牌关键词：#{keyword} ..."
  resp = search_brands(keyword)
  File.write(BRAND_SEARCH_CACHE, JSON.pretty_generate(resp))
  puts "原始响应已缓存：#{BRAND_SEARCH_CACHE}"

  results = resp.dig('data', 'results') || []
  puts "\n===== 匹配到的品牌（#{results.size} 个）====="
  results.each do |b|
    puts "- brandId=#{b['brandId']}  name=#{b['name']}  country=#{b['country']}  industries=#{(b['industries'] || []).join(',')}"
  end

  puts "\n请确认 Binance.US 的 brandId（一般是 binance.us），然后用："
  puts "  bundle exec rails runner scripts/fetch_brand_partners.rb <brandId> youtube"
  puts "继续拉取合作伙伴及联系方式。"
end

def run_fetch(brand_id, platform, with_email, force)
  creators_cache = File.join(CACHE_DIR, "brand_creators_#{sanitize(brand_id)}_#{platform}.json")
  contacts_cache = File.join(CACHE_DIR, "brand_contacts_#{sanitize(brand_id)}_#{platform}.json")

  # 已有联系方式缓存则直接读
  if !force && File.exist?(contacts_cache)
    puts "读取缓存联系方式：#{contacts_cache}"
    contacts = JSON.parse(File.read(contacts_cache))
    print_summary(contacts)
    return
  end

  # 1. 列出创作者
  creators = if !force && File.exist?(creators_cache)
               JSON.parse(File.read(creators_cache))
             else
               puts "调用 GET /sponsor/creators 拉取 #{brand_id} (#{platform}) 的合作伙伴..."
               r = list_sponsored_creators(brand_id, platform)
               File.write(creators_cache, JSON.pretty_generate(r))
               puts "创作者列表已缓存：#{creators_cache}（#{r.size} 人）"
               r
             end

  if creators.empty?
    puts '[提示] 未拉到创作者，请检查 brandId 是否正确（可先运行 search 确认）。'
    return
  end

  # 2. 逐个拉 profile（含 otherLinks/Telegram），可选拉真实邮箱
  puts "\n开始拉取 #{creators.size} 个创作者的联系方式（profile 2 积分/人#{with_email ? '，邮箱 15 积分/人' : ''}）..."
  contacts = creators.each_with_index.map do |c, i|
    id = c['creatorId']
    entry = c.dup
    if id.blank?
      entry['profile'] = { 'error' => '无 creatorId' }
    else
      entry['profile'] = api_post('/youtube/profile', { 'channelId' => id })
      if with_email && entry.dig('profile', 'data', 'hasEmail')
        entry['contact'] = api_post('/youtube/contact', { 'channelId' => id })
      end
    end
    puts "  [#{i + 1}/#{creators.size}] #{c['displayName']} done"
    entry
  end

  File.write(contacts_cache, JSON.pretty_generate(contacts))
  puts "联系方式已缓存：#{contacts_cache}"

  print_summary(contacts)
end

def print_summary(contacts)
  puts "\n===== 合作伙伴汇总（#{contacts.size} 人）====="
  contacts.each_with_index do |c, i|
    d = c.dig('profile', 'data') || {}
    links = d['otherLinks'] || []
    telegram = links.select { |l| (l['title'].to_s.downcase).include?('telegram') }.map { |l| l['url'] }
    emails = c.dig('contact', 'data', 'emails') || []
    email_txt = emails.any? ? emails.join(', ') : (d['hasEmail'] ? '有(未拉取)' : '无')
    puts sprintf("[%2d] %-28s 粉丝%-10s %s | 邮箱:%s | Telegram:%s",
                 i + 1, c['displayName'], c['followers'], c['country'],
                 email_txt, telegram.join(','))
  end
end

def run
  if API_KEY.blank?
    puts '[错误] 未设置 CREATORDB_API_KEY 环境变量'
    exit 1
  end
  FileUtils.mkdir_p(CACHE_DIR)

  cmd = ARGV[0]

  if cmd.nil? || cmd == 'search'
    run_search(ARGV[1] || 'binance')
  else
    brand_id   = cmd
    platform   = ARGV[1] || 'youtube'
    with_email = ARGV.include?('email')
    force      = ARGV.include?('refresh')
    run_fetch(brand_id, platform, with_email, force)
  end
end

run
