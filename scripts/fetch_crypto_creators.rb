# 获取「数字货币方向」的 YouTube 创作者（默认 10 条）
#
# 用法：
#   bundle exec rails runner scripts/fetch_crypto_creators.rb           # 有缓存则读缓存
#   bundle exec rails runner scripts/fetch_crypto_creators.rb refresh   # 强制重新拉取（会重新计费）
#
# 环境变量：CREATORDB_API_KEY（CreatorDB 的 API key）
# 缓存：tmp/creatordb/crypto_search.json   （/youtube/search 原始响应）
#       tmp/creatordb/crypto_profiles.json （/youtube/profile 详情结果）
# 说明：每次 /youtube/search 和 /youtube/profile 调用都会计费，
#       所以结果缓存到文件，避免重复调用浪费积分。

require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

API_KEY   = ENV['CREATORDB_API_KEY']
BASE_URL  = 'https://apiv3.creatordb.app'
LIMIT     = 10
CACHE_DIR = File.join(Rails.root, 'tmp', 'creatordb')
SEARCH_CACHE   = File.join(CACHE_DIR, 'crypto_search.json')
PROFILES_CACHE = File.join(CACHE_DIR, 'crypto_profiles.json')

def api_post(path, body)
  uri = URI("#{BASE_URL}#{path}")
  req = Net::HTTP::Post.new(uri)
  req['Content-Type'] = 'application/json'
  req['api-key'] = API_KEY
  req.body = body.to_json

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 30
  http.read_timeout = 90

  resp = http.request(req)
  JSON.parse(resp.body)
rescue => e
  { 'error' => e.message }
end

# 从 search 响应里健壮地提取 creator 数组（不同返回结构都尽量兼容）
def extract_creators(resp)
  arr = resp['data'] || resp['items'] || resp['creators'] || resp['results']
  arr = arr['items'] if arr.is_a?(Hash) && arr['items'].is_a?(Array)
  Array(arr).map do |c|
    {
      'channelId'   => c['channelId'] || c['id'],
      'uniqueId'    => c['uniqueId'],
      'displayName' => c['displayName'] || c['name'],
      'subscribers' => c['totalSubscribers'] || c['subscribers'],
      'raw'         => c
    }
  end
end

def run
  if API_KEY.blank?
    puts '[错误] 未设置 CREATORDB_API_KEY 环境变量'
    exit 1
  end

  FileUtils.mkdir_p(CACHE_DIR)
  force = ARGV.include?('refresh')

  # 已有详情缓存则直接读，不重复计费
  if !force && File.exist?(PROFILES_CACHE)
    puts "读取缓存详情：#{PROFILES_CACHE}"
    puts File.read(PROFILES_CACHE)
    return
  end

  # 1. 搜索（有缓存则读缓存）
  search = if !force && File.exist?(SEARCH_CACHE)
             JSON.parse(File.read(SEARCH_CACHE))
           else
             puts '调用 /youtube/search 搜索数字货币创作者（hashtags 过滤）...'
             r = api_post('/youtube/search', {
               'offset'   => 0,
               'pageSize' => LIMIT,
               'desc'     => true,
               'sortBy'   => 'totalSubscribers',
               'filters'  => [
                 { 'filterName' => 'hashtags', 'op' => 'in',
                   'value' => %w[crypto bitcoin ethereum blockchain cryptocurrency] }
               ]
             })
             File.write(SEARCH_CACHE, JSON.pretty_generate(r))
             puts "搜索结果已缓存：#{SEARCH_CACHE}"
             r
           end

  puts "\n===== /youtube/search 原始响应 ====="
  puts JSON.pretty_generate(search)

  creators = extract_creators(search)
  if creators.empty?
    puts "\n[警告] 未能从 search 响应中提取到 creator，请检查上方原始响应结构（可能字段名不同，或 hashtags 过滤无结果）"
    return
  end

  # 2. 拿详情（每个 creator 一次，计费）
  puts "\n调用 /youtube/profile 获取 #{creators.size} 个创作者详情..."
  profiles = creators.map do |c|
    id = c['channelId'].presence || c['uniqueId'].presence
    if id.blank?
      c.merge('profile' => { 'error' => '无 channelId/uniqueId' })
    else
      c.merge('profile' => api_post('/youtube/profile', { 'channelId' => id }))
    end
  end

  File.write(PROFILES_CACHE, JSON.pretty_generate(profiles))
  puts "详情已缓存：#{PROFILES_CACHE}"

  puts "\n===== 详情结果 ====="
  puts JSON.pretty_generate(profiles)
end

run
