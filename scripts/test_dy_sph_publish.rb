# 单独测试抖音 / 视频号 发布接口（参考 DySphHuashengPublishWorker 的发布逻辑）
#
# 用法：
#   只测抖音：  bundle exec rails runner 'scripts/test_dy_sph_publish.rb douyin'
#   只测视频号：bundle exec rails runner 'scripts/test_dy_sph_publish.rb weixin'
#   两个都测：  bundle exec rails runner 'scripts/test_dy_sph_publish.rb'
#
# 测试数据来源（二选一，优先级从上到下）：
#   1. 环境变量 TEXT + VIDEO_URL 手动指定
#        TEXT='你的文案' VIDEO_URL='https://...mp4?xxx' bundle exec rails runner 'scripts/test_dy_sph_publish.rb douyin'
#   2. 未指定时自动从 HuashengTask 取一条（pending 且 theme=花生视频-抖音号视频号 且 platform=抖音-视频号）
#
# 请求体（与 worker 的 publish 完全一致）：
#   { "profile_name": "douyin01", "text": <文案>, "video_oss_url": <视频URL> }
# 鉴权：走 RemoteApiClient（X-API-Key / X-Timestamp / X-Nonce / X-Signature）

# 发布接口主机（与 DySphHuashengPublishWorker::PUBLISH_HOST 保持一致；直接带协议，拼接时不再重复）
PUBLISH_HOST = "http://47.98.149.236:8080"
PROFILE_NAME = "douyin01"
THEME   = "花生视频-抖音号视频号"
PLATFORM = "抖音-视频号"

TARGETS = {
  "抖音"  => "/douyin/publish",
  "视频号" => "/weixin/publish"
}.freeze

OPEN_TIMEOUT = 30
READ_TIMEOUT = 600

# 根据命令行参数决定测哪些平台
def select_targets
  arg = ARGV[0].to_s.strip.downcase
  case arg
  when "douyin", "抖音"   then TARGETS.select { |k, _| k == "抖音" }
  when "weixin", "视频号" then TARGETS.select { |k, _| k == "视频号" }
  else TARGETS
  end
end

# 取测试数据：优先环境变量，否则从 HuashengTask 取一条
def fetch_test_data
  text = ENV['TEXT']
  video_url = ENV['VIDEO_URL']

  if !text.to_s.empty? && !video_url.to_s.empty?
    return { text: text, video_url: video_url, from: "环境变量" }
  end

  task = HuashengTask.where(status: :pending, theme: THEME, platform: PLATFORM).order(:id).first
  if task
    { text: task.title.to_s, video_url: task.oss_url.to_s, from: "HuashengTask##{task.id}" }
  else
    nil
  end
end

# 发布到单个平台端点
def publish(endpoint, platform_name, text, video_url)
  body = { profile_name: PROFILE_NAME, text: text, video_oss_url: video_url }
  url  = "#{PUBLISH_HOST}#{endpoint}"

  puts "\n===== #{platform_name} ====="
  puts "URL:  #{url}"
  puts "Body: #{body.to_json}"

  response = RemoteApiClient.post(url, body, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
  puts "HTTP: #{response.code}"
  puts "响应: #{response.body}"

  parsed = begin
    JSON.parse(response.body)
  rescue JSON::ParserError
    nil
  end

  if parsed.is_a?(Hash) && parsed["type"] == "success"
    puts "=> #{platform_name} 发布成功 ✅"
    { success: true }
  else
    err = parsed.is_a?(Hash) ? (parsed["error_info"] || parsed["error"] || parsed["message"]) : nil
    puts "=> #{platform_name} 发布失败 ❌ #{err || response.body}"
    { success: false }
  end
rescue => e
  puts "=> #{platform_name} 请求异常 ❌ #{e.class}: #{e.message}"
  { success: false }
end

# ===== 主流程 =====
data = fetch_test_data

if data.nil?
  puts "无测试数据：HuashengTask 无 pending 任务，且未设置 TEXT/VIDEO_URL 环境变量。"
  puts "可用环境变量手动指定："
  puts "  TEXT='你的文案' VIDEO_URL='https://...mp4?xxx' bundle exec rails runner 'scripts/test_dy_sph_publish.rb douyin'"
  exit 1
end

puts "测试数据来源: #{data[:from]}"
puts "text:      #{data[:text]}"
puts "video_url: #{data[:video_url]}"

results = {}
select_targets.each do |platform_name, endpoint|
  results[platform_name] = publish(endpoint, platform_name, data[:text], data[:video_url])
end

puts "\n===== 汇总 ====="
results.each { |k, r| puts "#{k}: #{r[:success] ? '成功' : '失败'}" }
