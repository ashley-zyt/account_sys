require_relative "../config/environment"

OSS_BUCKET = "jianying-rd".freeze
OSS_REGION = "cn-hangzhou".freeze
OSS_ACCESS_KEY_ID = "gZL8z938T19mSUHf".freeze
OSS_ACCESS_KEY_SECRET = "A9fSDa9cH5YAExpEUR4QSizkFQEcrS".freeze

def percent_encode(str)
  URI.encode_www_form_component(str).gsub("+", "%20")
end

def percent_encode_path(path)
  path.split("/").map { |seg| percent_encode(seg) }.join("/")
end

def oss_v1_sign_url(key, expires_seconds = 31536000)
  return nil if key.blank?
  require "openssl"
  require "base64"

  expires = (Time.now.utc.to_i + expires_seconds).to_s
  key = key.sub(%r{^/}, "")
  string_to_sign = "GET\n\n\n#{expires}\n/#{OSS_BUCKET}/#{key}"
  signature = Base64.strict_encode64(
    OpenSSL::HMAC.digest("sha1", OSS_ACCESS_KEY_SECRET, string_to_sign)
  ).strip

  encoded_key = key.split("/").map { |seg| percent_encode(seg) }.join("/")
  "https://#{OSS_BUCKET}.oss-#{OSS_REGION}.aliyuncs.com/#{encoded_key}?" \
    "OSSAccessKeyId=#{OSS_ACCESS_KEY_ID}" \
    "&Expires=#{expires}" \
    "&Signature=#{percent_encode(signature)}"
end

total_count = JianyingTask.count
updated_count = 0
youtube_title_adjusted_count = 0
failed_count = 0

puts "开始批量更新 JianyingTask 数据..."
puts "总记录数: #{total_count}"
puts "=" * 60

JianyingTask.find_each(batch_size: 100) do |task|
  begin
    updates = {}

    if task.oss_url.present? 
      full_url = oss_v1_sign_url(task.oss_url)
      updates[:full_oss_url] = task.oss_url if task.oss_url.present?
      updates[:oss_url] = full_url if full_url.present?
    end

    if task.platform == "youtube" && task.title.present?
      title = task.title.strip
      if title.length > 99
        updates[:title] = title[0...99]
        updates[:description] = title[99..-1]
        youtube_title_adjusted_count += 1
      end
    end

    unless updates.empty?
      task.update!(updates)
      updated_count += 1
    end

    print "\r进度: #{updated_count}/#{total_count}"
  rescue => e
    failed_count += 1
    puts "\n任务 #{task.task_uuid} 更新失败: #{e.message}"
  end
  break
end

puts "\n"
puts "=" * 60
puts "更新完成!"
puts "成功更新: #{updated_count} 条"
puts "调整YouTube标题: #{youtube_title_adjusted_count} 条"
puts "更新失败: #{failed_count} 条"