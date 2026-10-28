# 按品牌获取「合作伙伴（被赞助创作者）」列表（基础信息），可选再拉联系方式
#
# 用法：
#   bundle exec rails runner scripts/fetch_brand_partners.rb search [关键词]         # 搜索品牌（默认 binance）
#   bundle exec rails runner scripts/fetch_brand_partners.rb <brandId> [platform] [limit]
#   bundle exec rails runner scripts/fetch_brand_partners.rb binance.us youtube 5      # 先预览 5 条
#   bundle exec rails runner scripts/fetch_brand_partners.rb binance.us youtube 5 sort=lastSponsoredDate  # 按最新合作排序
#   bundle exec rails runner scripts/fetch_brand_partners.rb binance.us youtube 500    # 拉前 500 条基础信息
#   bundle exec rails runner scripts/fetch_brand_partners.rb binance.us youtube 500 contacts   # 对已拉取的再拉联系方式(profile)
#   bundle exec rails runner scripts/fetch_brand_partners.rb binance.us sample 500             # 两平台各500条 + 每人联系方式
#
#   sortBy 可选：lastSponsoredDate(默认/最新合作) / followers / avgRecentSponsoredEngagementRate / sponsoredCount
#
# 环境变量：CREATORDB_API_KEY
# 缓存目录：tmp/creatordb/
#   brand_search.json            品牌搜索结果
#   brand_creators_<brand>.json  品牌赞助的创作者列表（基础信息）
#   brand_contacts_<brand>.json  创作者 profile(含社交链接/Telegram)
#
# 说明：
#   - 默认只拉「基础信息」（/sponsor/creators 已含 displayName/followers/country/topics/niches/sponsoredCount 等），
#     不逐人调 profile，也不拉邮箱，避免一次性耗用过多积分。
#   - 只有显式加 contacts（或 sample/both）才会逐人调 profile，只取联系方式字段（约 0.3 积分/人）；
#     再加 email 才会调 contact 取真实邮箱（15 积分/人）。

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

def ts(ms)
  return '' if ms.to_i.zero?
  Time.at(ms.to_i / 1000).strftime('%Y-%m-%d')
rescue
  ''
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

# 分页拉取某品牌在某平台赞助的创作者，最多 limit 条，返回数组（基础信息）
def list_sponsored_creators(brand_id, platform, limit, sort_by = 'lastSponsoredDate')
  all = []
  offset = 0
  loop do
    break if all.size >= limit
    r = api_get('/sponsor/creators', {
      'brandId'  => brand_id,
      'platform' => platform,
      'pageSize' => [100, limit - all.size].min,
      'offset'   => offset,
      'sortBy'   => sort_by,
      'desc'     => 'true'
    })
    break if r['error']

    data = r['data'] || {}
    batch = data['creators'] || []
    all.concat(batch)
    total = data['totalResults'].to_i
    offset += batch.size
    break if batch.empty? || offset >= total
  end
  all.first(limit)
end

def fetch_and_cache_creators(brand_id, platform, limit, sort_by)
  creators_cache = File.join(CACHE_DIR, "brand_creators_#{sanitize(brand_id)}_#{platform}.json")
  puts "拉取 #{brand_id} (#{platform}) 合作伙伴（最多 #{limit} 条，按 #{sort_by} 排序）..."
  r = list_sponsored_creators(brand_id, platform, limit, sort_by)
  File.write(creators_cache, JSON.pretty_generate(r))
  puts "列表已缓存：#{creators_cache}（#{r.size} 条）"
  r
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
  puts "\n确认 brandId 后运行："
  puts "  bundle exec rails runner scripts/fetch_brand_partners.rb <brandId> youtube 5"
end

def run_list(brand_id, platform, limit, force, sort_by = 'lastSponsoredDate')
  creators_cache = File.join(CACHE_DIR, "brand_creators_#{sanitize(brand_id)}_#{platform}.json")

  creators = if !force && File.exist?(creators_cache)
               cached = JSON.parse(File.read(creators_cache))
               cached.size >= limit ? cached : fetch_and_cache_creators(brand_id, platform, limit, sort_by)
             else
               fetch_and_cache_creators(brand_id, platform, limit, sort_by)
             end
  creators = creators.first(limit)

  if creators.empty?
    puts '[提示] 未拉到创作者，请检查 brandId 是否正确（可先运行 search 确认）。'
    return
  end

  puts "\n===== 合作伙伴基础信息（#{creators.size} 条）====="
  creators.each_with_index do |c, i|
    puts sprintf("[%3d] %-30s 粉丝%-10s %s | 赞助内容%d条 | 主题:%s | 最近赞助:%s",
                 i + 1,
                 c['displayName'],
                 c['followers'],
                 c['country'],
                 c['sponsoredCount'].to_i,
                 (c['topics'] || []).join('/'),
                 ts(c['lastSponsoredDate']))
  end
end

def run_contacts(brand_id, platform, limit, with_email, force, sort_by = 'lastSponsoredDate')
  creators_cache = File.join(CACHE_DIR, "brand_creators_#{sanitize(brand_id)}_#{platform}.json")
  contacts_cache = File.join(CACHE_DIR, "brand_contacts_#{sanitize(brand_id)}_#{platform}.json")

  creators = if !force && File.exist?(creators_cache)
               cached = JSON.parse(File.read(creators_cache))
               cached.size >= limit ? cached : fetch_and_cache_creators(brand_id, platform, limit, sort_by)
             else
               fetch_and_cache_creators(brand_id, platform, limit, sort_by)
             end
  creators = creators.first(limit)

  # 读取已拉取的部分结果，按 creatorId 索引，支持断点续拉
  done = {}
  if !force && File.exist?(contacts_cache)
    begin
      JSON.parse(File.read(contacts_cache)).each do |e|
        done[e['creatorId']] = e if e && e['creatorId']
      end
    rescue JSON::ParserError
      done = {}
    end
  end

  todo = creators.reject { |c| done.key?(c['creatorId']) }

  if todo.empty?
    puts "所有创作者的联系方式均已缓存（#{done.size} 人）。"
    print_contacts_summary(creators.map { |c| done[c['creatorId']] }.compact)
    return
  end

  puts "\n开始拉取联系方式（已缓存 #{done.size} 人，待拉 #{todo.size} 人；联系方式字段约 0.3 积分/人#{with_email ? '，邮箱 15 积分/人' : ''}）..."
  todo.each do |c|
    id = c['creatorId']
    entry = c.dup
    if id.blank?
      entry['profile'] = { 'error' => '无 creatorId' }
    else
      entry['profile'] = profile_call(platform, id)
      if with_email && entry.dig('profile', 'data', 'hasEmail')
        entry['contact'] = contact_call(platform, id)
      end
    end
    done[id] = entry
    # 每拉完一个立即写盘，中断不丢已拉取的数据
    File.write(contacts_cache, JSON.pretty_generate(done.values))
    puts "  [#{done.size}/#{creators.size}] #{c['displayName']} done（已写盘）"
  end

  print_contacts_summary(creators.map { |c| done[c['creatorId']] }.compact)
end

def print_contacts_summary(contacts)
  puts "\n===== 合作伙伴联系方式（#{contacts.size} 人）====="
  contacts.each_with_index do |c, i|
    d = c.dig('profile', 'data') || {}
    links = d['otherLinks'] || []
    telegram = links.select { |l| (l['title'].to_s.downcase).include?('telegram') }.map { |l| l['url'] }
    emails = c.dig('contact', 'data', 'emails') || []
    email_txt = emails.any? ? emails.join(', ') : (d['hasEmail'] ? '有(未拉取)' : '无')
    puts sprintf("[%3d] %-30s 粉丝%-10s %s | 邮箱:%s | Telegram:%s",
                 i + 1, c['displayName'], c['followers'], c['country'],
                 email_txt, telegram.join(','))
  end
end

# 只拉「联系方式相关」字段（fractional，比全量 profile 便宜）；未开启 Fractional Calls 时自动降级全量
CONTACT_FIELDS = ['otherLinks', 'hasEmail', 'bio'].freeze

def profile_call(platform, id)
  body = platform == 'youtube' ? { 'channelId' => id } : { 'uniqueId' => id }
  body['fields'] = CONTACT_FIELDS
  resp = api_post("/#{platform}/profile", body)

  # 未开启 Fractional Calls 时带 fields 会报错，降级为全量 profile
  if resp['errorCode'].to_s.downcase.include?('fractional')
    resp = api_post("/#{platform}/profile", body.except('fields'))
  end
  resp
end

def contact_call(platform, id)
  body = platform == 'youtube' ? { 'channelId' => id } : { 'uniqueId' => id }
  api_post("/#{platform}/contact", body)
end

def run_sample(brand_id, limit, sort_by, with_email, force)
  %w[youtube instagram].each do |platform|
    puts "\n#{'=' * 70}\n平台：#{platform}（#{brand_id}）\n#{'=' * 70}"
    run_contacts(brand_id, platform, limit, with_email, force, sort_by)
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
    sort_by    = (ARGV.find { |a| a.start_with?('sort=') } || '').split('=', 2)[1] || 'lastSponsoredDate'
    with_email = ARGV.include?('email')
    force      = ARGV.include?('refresh')

    if ARGV[1] == 'sample' || ARGV[1] == 'both'
      limit = (ARGV[2] || '500').to_i
      run_sample(brand_id, limit, sort_by, with_email, force)
    else
      platform   = ARGV[1] || 'youtube'
      limit      = (ARGV[2] || '5').to_i
      with_contacts = ARGV.include?('contacts')

      if with_contacts
        run_contacts(brand_id, platform, limit, with_email, force, sort_by)
      else
        run_list(brand_id, platform, limit, force, sort_by)
      end
    end
  end
end

run
