# 获取「数字货币方向」的 YouTube 创作者（默认 10 条）
#
# 用法：
#   bundle exec rails runner scripts/fetch_crypto_creators.rb           # 有缓存则读缓存
#   bundle exec rails runner scripts/fetch_crypto_creators.rb refresh   # 强制重新拉取（重新计费）
#
# 环境变量：CREATORDB_API_KEY（CreatorDB 的 API key）
# 缓存：tmp/creatordb/youtube_topics.json   （/youtube/topics 主题目录）
#       tmp/creatordb/crypto_search.json     （/youtube/search 原始响应）
#       tmp/creatordb/crypto_profiles.json   （/youtube/profile 详情）
# 说明：每次调用都计费，结果缓存到文件避免重复付费。
# 流程：先列主题目录(GET) → 精确匹配 crypto 相关主题 → 用主题 id 搜索 → 拿详情。

require 'net/http'
require 'json'
require 'uri'
require 'fileutils'

API_KEY   = ENV['CREATORDB_API_KEY']
BASE_URL  = 'https://apiv3.creatordb.app'
LIMIT     = 10
CACHE_DIR = File.join(Rails.root, 'tmp', 'creatordb')
TOPICS_CACHE   = File.join(CACHE_DIR, 'youtube_topics.json')
SEARCH_CACHE   = File.join(CACHE_DIR, 'crypto_search.json')
PROFILES_CACHE = File.join(CACHE_DIR, 'crypto_profiles.json')

# crypto 主题匹配关键词（小写）
CRYPTO_KEYWORDS = %w[crypto bitcoin blockchain cryptocurrency ethereum defi web3 nft altcoin token]

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

def api_get(path)
  http_request(Net::HTTP::Get, path)
end

def api_post(path, body = {})
  http_request(Net::HTTP::Post, path, body)
end

# 从 topics 响应里健壮提取主题数组（/youtube/topics 的 data 是数组）
def extract_topics(resp)
  data = resp['data']
  raw = data.is_a?(Hash) ? (data['topics'] || data['topicList'] || data['items']) : data
  Array(raw)
end

# 筛出 crypto 相关主题，保留完整对象（含 id/name/category）
def find_crypto_topics(resp)
  extract_topics(resp).select do |t|
    next false unless t.is_a?(Hash)
    hay = [t['name'], t['topicName'], t['id'], t['category']].compact.join(' ').downcase
    CRYPTO_KEYWORDS.any? { |k| hay.include?(k) }
  end
end

# 从 search 响应里健壮提取 creator 数组（/youtube/search 的 data.creatorList）
def extract_creators(resp)
  data = resp['data']
  arr = data.is_a?(Hash) ? (data['creatorList'] || data['items'] || data['creators'] || data['results']) : data
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

  # 已有详情缓存则直接读
  if !force && File.exist?(PROFILES_CACHE)
    puts "读取缓存详情：#{PROFILES_CACHE}"
    puts File.read(PROFILES_CACHE)
    return
  end

  # 1. 列主题目录（GET，缓存）
  topics_resp = if !force && File.exist?(TOPICS_CACHE)
                  JSON.parse(File.read(TOPICS_CACHE))
                else
                  puts '调用 GET /youtube/topics 列出主题目录...'
                  r = api_get('/youtube/topics')
                  File.write(TOPICS_CACHE, JSON.pretty_generate(r))
                  puts "主题目录已缓存：#{TOPICS_CACHE}"
                  r
                end

  all_topics = extract_topics(topics_resp)
  puts "\n===== 主题目录概况：共 #{all_topics.size} 个主题，样例 ====="
  puts JSON.pretty_generate(all_topics.first(3))

  crypto_topics = find_crypto_topics(topics_resp)
  puts "\n===== 匹配到的 crypto 相关主题（#{crypto_topics.size} 个）====="
  puts JSON.pretty_generate(crypto_topics)

  if crypto_topics.empty?
    puts "\n[提示] 未匹配到 crypto 主题。请把上方主题目录样例贴回来，或打开 #{TOPICS_CACHE} 查看完整列表。"
    return
  end

  # 取主题 id（topics filter 用 id，如 id_cryptocurrency_Finance）
  topic_ids = crypto_topics.map { |t| t['id'] || t['topicId'] || t['value'] }.compact
  if topic_ids.empty?
    puts "\n[提示] 主题对象里没有 id/topicId/value 字段，请检查上方 crypto_topics 结构"
    return
  end
  puts "\n用主题 id 搜索：#{topic_ids.inspect}"

  # 2. 搜索（POST，缓存）
  search = if !force && File.exist?(SEARCH_CACHE)
             JSON.parse(File.read(SEARCH_CACHE))
           else
             puts '调用 POST /youtube/search 搜索（topics 过滤）...'
             r = api_post('/youtube/search', {
               'offset'   => 0,
               'pageSize' => LIMIT,
               'desc'     => true,
               'sortBy'   => 'totalSubscribers',
               'filters'  => [
                 { 'filterName' => 'topics', 'op' => 'in', 'value' => topic_ids }
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
    puts "\n[警告] 未能从 search 响应中提取到 creator，请检查上方原始响应结构"
    return
  end

  # 3. 拿详情
  puts "\n调用 POST /youtube/profile 获取 #{creators.size} 个创作者详情..."
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
