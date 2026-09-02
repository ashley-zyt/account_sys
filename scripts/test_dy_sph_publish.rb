# 单独测试抖音 / 视频号 发布接口（POST /accounts/publish_video，platform 字段区分平台）
#
# 用法：
#   只测抖音：  bundle exec rails runner scripts/test_dy_sph_publish.rb douyin
#   只测视频号：bundle exec rails runner scripts/test_dy_sph_publish.rb shipinhao
#   两个都测：  bundle exec rails runner scripts/test_dy_sph_publish.rb
#
# 必填环境变量：
#   PROFILE_NAME  指纹浏览器 profile 名
#   TITLE         标题/文案（话题用 # 前缀直接写在文案里）
#   视频来源二选一（VIDEO_URL 优先）：
#     VIDEO_URL   视频 URL（服务端先下载到本地临时文件再发布，结束后自动删除）
#     VIDEO_PATH  远端机器本地视频绝对路径（必须真实存在）
# 示例（用 URL，可直接用 task.oss_url）：
#   PROFILE_NAME='douyin_fb_001' VIDEO_URL='https://xxx/test.mp4' TITLE='测试文案 #话题' \
#     bundle exec rails runner scripts/test_dy_sph_publish.rb douyin
#
# 平台专属覆盖（可选，同时测两个平台时各自用不同参数）：
#   PROFILE_NAME_DOUYIN / PROFILE_NAME_SHIPINHAO
#   VIDEO_URL_DOUYIN / VIDEO_URL_SHIPINHAO
#   VIDEO_PATH_DOUYIN / VIDEO_PATH_SHIPINHAO
#   TITLE_DOUYIN / TITLE_SHIPINHAO
# 其他可选：ACCOUNT_ID、HOST、PORT、WAIT_SECONDS、UNDETECTABLE_PATH

PUBLISH_HOST = "http://47.98.149.236:8080"   # 127.0.0.1 已替换为 47.98.149.236
ENDPOINT = "/accounts/publish_video"

PLATFORM_NAMES = {
  "douyin"    => "抖音",
  "shipinhao" => "视频号"
}.freeze

OPEN_TIMEOUT = 30
READ_TIMEOUT = 900   # 发布流程超时上限 15 分钟，读超时放宽

# 取环境变量：先查平台专属 <KEY>_<PLATFORM>，再查通用 <KEY>
def env_for(platform, key)
  ENV["#{key}_#{platform.upcase}"].presence || ENV[key].presence
end

# 根据命令行参数决定测哪些平台
def select_platforms
  arg = ARGV[0].to_s.strip.downcase
  case arg
  when "douyin", "抖音"     then ["douyin"]
  when "shipinhao", "视频号" then ["shipinhao"]
  else ["douyin", "shipinhao"]
  end
end

# 构造请求体
def build_body(platform)
  body = {
    "profile_name" => env_for(platform, "PROFILE_NAME").to_s,
    "platform"     => platform,
    "title"        => env_for(platform, "TITLE").to_s
  }

  # 视频来源：video_url 优先，为空时用 video_path
  video_url  = env_for(platform, "VIDEO_URL").to_s
  video_path = env_for(platform, "VIDEO_PATH").to_s
  if !video_url.empty?
    body["video_url"] = video_url
  elsif !video_path.empty?
    body["video_path"] = video_path
  end

  body["account_id"]        = ENV['ACCOUNT_ID'].to_i if ENV['ACCOUNT_ID'].present?
  body["host"]              = ENV['HOST'] if ENV['HOST'].present?
  body["port"]              = ENV['PORT'].to_i if ENV['PORT'].present?
  body["wait_seconds"]      = ENV['WAIT_SECONDS'].to_i if ENV['WAIT_SECONDS'].present?
  body["undetectable_path"] = ENV['UNDETECTABLE_PATH'] if ENV['UNDETECTABLE_PATH'].present?
  body
end

# 发布到单个平台
def publish(platform)
  body = build_body(platform)
  url  = "#{PUBLISH_HOST}#{ENDPOINT}"

  puts "\n===== #{PLATFORM_NAMES[platform]} (#{platform}) ====="
  puts "URL:  #{url}"
  puts "Body: #{body.to_json}"

  response = RemoteApiClient.post(url, body, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
  puts "HTTP: #{response.code}"

  # Net::HTTP 响应体默认 ASCII-8BIT，含中文时会与 UTF-8 字符串拼接报编码冲突；先按 UTF-8 解释
  resp_body = response.body.to_s.dup.force_encoding('UTF-8')
  puts "响应: #{resp_body}"

  parsed = begin
    JSON.parse(resp_body)
  rescue JSON::ParserError
    nil
  end

  if parsed.is_a?(Hash) && parsed["type"] == "success"
    puts "=> #{PLATFORM_NAMES[platform]} 发布成功 ✅ (status=#{parsed["status"]}, profile_id=#{parsed["profile_id"]})"
    { success: true }
  else
    err = parsed.is_a?(Hash) ? parsed["error_info"] : nil
    puts "=> #{PLATFORM_NAMES[platform]} 发布失败 ❌ #{err || resp_body}"
    { success: false }
  end
rescue => e
  puts "=> #{PLATFORM_NAMES[platform]} 请求异常 ❌ #{e.class}: #{e.message}"
  { success: false }
end

# ===== 主流程 =====
platforms = select_platforms

missing = []
platforms.each do |platform|
  missing << "PROFILE_NAME" if env_for(platform, "PROFILE_NAME").to_s.empty?
  missing << "TITLE"        if env_for(platform, "TITLE").to_s.empty?
  vurl  = env_for(platform, "VIDEO_URL").to_s
  vpath = env_for(platform, "VIDEO_PATH").to_s
  missing << "VIDEO_URL 或 VIDEO_PATH" if vurl.empty? && vpath.empty?
end
if missing.any?
  puts "缺少必填环境变量: #{missing.uniq.join(', ')}"
  puts ""
  puts "示例（用 URL）："
  puts "  PROFILE_NAME='douyin_fb_001' VIDEO_URL='https://xxx/test.mp4' TITLE='测试文案 #话题' \\"
  puts "    bundle exec rails runner scripts/test_dy_sph_publish.rb douyin"
  exit 1
end

results = {}
platforms.each do |platform|
  results[platform] = publish(platform)
end

puts "\n===== 汇总 ====="
results.each { |k, r| puts "#{PLATFORM_NAMES[k]}: #{r[:success] ? '成功' : '失败'}" }
