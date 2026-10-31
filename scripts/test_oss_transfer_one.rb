# ===== 用指定 URL 测试转存一条视频 =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/test_oss_transfer_one.rb
#   bundle exec rails runner scripts/test_oss_transfer_one.rb "https://xxx.mp4"
#
# 走完整链路：解析 URL → 查源对象存在性 → 转存 → 验证目标对象已写入。

url = ARGV[0] || "https://jianying-rd.oss-cn-hangzhou.aliyuncs.com/video/IR-f6c6b382cc880f80.mp4"

puts "===== 单条视频转存测试 ====="
puts "输入 URL: #{url[0, 120]}"
puts

# 1. 解析 bucket / key
bucket = OssTransfer.bucket_from_url(url)
key    = OssTransfer.key_from_url(url)
puts "[解析] bucket=#{bucket.inspect}  key=#{key.inspect}"
puts

if bucket.blank? || key.blank?
  puts "❌ 无法解析 bucket/key，结束"
else
  # 2. 源对象存在性
  src_client = OssTransfer.oss_client(*OssTransfer.source_credentials)
  begin
    src_exists = src_client.get_bucket(bucket).object_exists?(key)
    puts "[源对象] #{bucket}/#{key} 存在: #{src_exists}"
  rescue => e
    puts "[源对象] ❌ #{e.class}: #{e.message[0, 120]}"
  end
  puts

  # 3. 转存
  puts "[转存] 开始..."
  result = OssTransfer.transfer(bucket, key)
  if result.nil?
    puts "[转存] ❌ 失败"
  else
    new_key, new_url = result
    puts "[转存] ✅ 成功"
    puts "  new_key = #{new_key}"
    puts "  new_url = #{new_url}"
    puts

    # 4. 验证目标对象已写入
    dst_client = OssTransfer.oss_client(*OssTransfer.dest_credentials)
    dest_bucket = OssTransfer::BUCKET_MAP[bucket]
    begin
      dst_exists = dst_client.get_bucket(dest_bucket).object_exists?(new_key)
      puts "[验证] 目标 #{dest_bucket}/#{new_key} 存在: #{dst_exists}"
    rescue => e
      puts "[验证] ❌ #{e.class}: #{e.message[0, 120]}"
    end
  end
end

puts
puts "===== 完成 ====="
