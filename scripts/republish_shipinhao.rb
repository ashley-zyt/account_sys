# 单独补发「视频号」（用于「抖音-视频号」合并任务中抖音成功、视频号失败的情况）
#
# 用法：
#   bundle exec rails runner scripts/republish_shipinhao.rb               # 预览最新一条 failed 任务（不发布）
#   bundle exec rails runner scripts/republish_shipinhao.rb confirm       # 补发最新一条 failed 任务的视频号
#   bundle exec rails runner scripts/republish_shipinhao.rb <id> confirm  # 指定任务 id 补发
#
# 说明：只调视频号发布接口（platform=shipinhao），复用任务的 oss_url + title；
#       成功则把任务标记 success，失败保持 failed 并更新 error_msg。

require 'json'

THEME        = "花生视频-抖音号视频号"
PLATFORM     = "抖音-视频号"
PUBLISH_HOST = "http://47.98.149.236:8080"
PROFILE_NAME = "domestic01"
OPEN_TIMEOUT = 30
READ_TIMEOUT = 900

def find_task
  if (id = ARGV[0].to_i) > 0
    HuashengTask.find_by(id: id)
  else
    HuashengTask.where(theme: THEME, platform: PLATFORM, status: :failed)
                .order(updated_at: :desc).first
  end
end

def publish_shipinhao(task)
  body = {
    "profile_name" => PROFILE_NAME,
    "platform"     => "shipinhao",
    "video_url"    => task.oss_url.to_s,
    "title"        => task.title.to_s
  }
  url = "#{PUBLISH_HOST}/accounts/publish_video"
  puts "\n请求: #{url}"
  puts "Body: #{body.to_json}"

  resp = RemoteApiClient.post(url, body, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
  parsed = begin
    JSON.parse(resp.body.to_s.dup.force_encoding('UTF-8'))
  rescue JSON::ParserError
    nil
  end

  # 成功判定：type 只表示「请求被处理」，status=="completed" 才是真正发布成功
  if parsed.is_a?(Hash) && parsed["type"] == "success" && parsed["status"] == "completed"
    { success: true, message: "成功" }
  else
    err = parsed.is_a?(Hash) ? (parsed["error_info"] || parsed["status"]) : resp.body.to_s
    { success: false, message: err.to_s }
  end
rescue => e
  { success: false, message: "#{e.class} #{e.message}" }
end

confirm = ARGV.include?('confirm')
task = find_task

if task.nil?
  puts "未找到 failed 的「#{PLATFORM}」任务"
  exit 1
end

puts "任务: id=#{task.id} keyword=#{task.keyword}"
puts "标题: #{task.title}"
puts "当前状态: #{task.status} | 错误: #{task.error_msg}"
puts "创建: #{task.created_at} | 更新: #{task.updated_at}"

unless confirm
  puts "\n[预览] 未发布。确认无误后加 confirm 参数执行补发视频号。"
  exit 0
end

result = publish_shipinhao(task)
puts "\n视频号发布结果: #{result[:message]}"

if result[:success]
  task.update_columns(
    status: HuashengTask.statuses[:success],
    actual_publish_time: Time.current,
    error_msg: nil,
    updated_at: Time.current
  )
  puts "✅ 已把任务 #{task.id} 标记为 success"
else
  task.update_columns(
    error_msg: "抖音:成功；视频号:失败(#{result[:message]})",
    updated_at: Time.current
  )
  puts "❌ 视频号仍失败，任务保持 failed。错误: #{result[:message]}"
end
