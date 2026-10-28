# 测试：拉取 1 个创作者的主语言字段
#
# 用法：
#   bundle exec rails runner scripts/test_fetch_language.rb              # 取缓存里第一个创作者
#   bundle exec rails runner scripts/test_fetch_language.rb UCxxxxxx    # 指定 channelId
#
# 说明：用 /youtube/profile 的 fractional 字段，只拉 mainLanguage，单次约 0.1 积分。

require 'net/http'
require 'json'
require 'uri'

API_KEY  = ENV['CREATORDB_API_KEY']
BASE_URL = 'https://apiv3.creatordb.app'
CACHE_FILE = Rails.root.join('tmp', 'creatordb', 'brand_contacts_binance.us_youtube.json')

def api_post(path, body = {})
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

def run
  if API_KEY.blank?
    puts '[错误] 未设置 CREATORDB_API_KEY 环境变量'
    exit 1
  end

  channel_id = ARGV[0]
  if channel_id.blank?
    data = JSON.parse(File.read(CACHE_FILE))
    first = data.find { |d| d['creatorId'].present? }
    channel_id = first['creatorId']
    puts "未指定 channelId，取缓存第一个：#{first['displayName']} (#{channel_id})"
  end

  puts "\n调用 /youtube/profile 拉取主语言字段..."
  resp = api_post('/youtube/profile', {
    'channelId' => channel_id,
    'fields'    => ['mainLanguage']
  })

  puts "\n===== 原始响应 ====="
  puts JSON.pretty_generate(resp)

  d = resp['data'] || {}
  puts "\n===== 语言字段 ====="
  puts "mainLanguage  : #{d['mainLanguage'].inspect}"
end

run
