# ===== 分步诊断单条转存失败点（捕获每步原始异常） =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/diagnose_transfer_one.rb
#
# 绕过 OssTransfer.transfer 的 rescue，逐层执行并打印异常，定位是读源/读内容/写目标哪一步失败。

key = "video/IR-f6c6b382cc880f80.mp4"
src_name = "jianying-rd"
dst_name = "jianying-rd-videos"

src_client = OssTransfer.oss_client(*OssTransfer.source_credentials)
dst_client = OssTransfer.oss_client(*OssTransfer.dest_credentials)

puts "===== 分步转存诊断 ====="
puts "key=#{key}"
puts

# D1. 读源对象
begin
  src_bucket = src_client.get_bucket(src_name)
  obj = src_bucket.get_object(key)
  puts "[D1 读源] ✅ obj.class=#{obj.class}"
rescue => e
  puts "[D1 读源] ❌ #{e.class}: #{e.message[0, 150]}"
end
puts

# D2. 读取内容
begin
  content = obj.respond_to?(:read) ? obj.read : obj.body
  puts "[D2 内容] ✅ content.class=#{content.class} bytesize=#{content.to_s.bytesize}"
rescue => e
  puts "[D2 内容] ❌ #{e.class}: #{e.message[0, 150]}"
  content = nil
end
puts

# D3. 目标 bucket + object_exists?
begin
  dst_bucket = dst_client.get_bucket(dst_name)
  exists = dst_bucket.object_exists?(key)
  puts "[D3 目标] ✅ get_bucket 成功，object_exists?=#{exists}"
rescue => e
  puts "[D3 目标] ❌ #{e.class}: #{e.message[0, 150]}"
  dst_bucket = nil
end
puts

# D4. 写目标
if content && dst_bucket
  begin
    dst_bucket.put_object(key, content: content)
    puts "[D4 写入] ✅ put_object 成功"
  rescue => e
    puts "[D4 写入] ❌ #{e.class}: #{e.message[0, 150]}"
    puts e.backtrace.first(8).join("\n")
  end
else
  puts "[D4 写入] 跳过（前置步骤失败）"
end
puts

puts "===== 诊断完成 ====="
