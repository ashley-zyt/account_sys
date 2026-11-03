# 测试跨地域复制到香港 bucket account-agic 的耗时
#
# 用法：
#   bundle exec rails runner scripts/test_copy_to_hk.rb
#   bundle exec rails runner scripts/test_copy_to_hk.rb <src_bucket> <src_key>
#
# 说明：
#   [1] 用 OSS 服务端 copy_object 尝试跨地域复制（杭州→香港，官方不支持，预期报错）
#   [2] 用 download+upload 方式跨地域复制（经过服务器，测实际耗时）
require 'aliyun/oss'

MAIN_ID     = ENV['ALIYUN_ACCESS_KEY_ID']
MAIN_SECRET = ENV['ALIYUN_ACCESS_KEY_SECRET']

HZ_ENDPOINT = 'https://oss-cn-hangzhou.aliyuncs.com'
HK_ENDPOINT = 'https://oss-cn-hongkong.aliyuncs.com'
DEST_BUCKET = 'account-agic'

src_bucket = ARGV[0] || 'grok-videos'
src_key    = ARGV[1] || 'grok-video-04efa151-4c39-435f-a041-2c7090a8eb2c_3.mp4'

dest_key = "timeout/#{src_key}"
puts "源:   #{src_bucket}/#{src_key}"
puts "目标: #{DEST_BUCKET}/#{dest_key}"
puts

# [1] copy_object（跨地域，预期不支持）
puts "[1] copy_object 跨地域复制"
begin
  hk = Aliyun::OSS::Client.new(endpoint: HK_ENDPOINT, access_key_id: MAIN_ID, access_key_secret: MAIN_SECRET)
  t = Time.now
  hk.get_bucket(DEST_BUCKET).copy_object(dest_key, "/#{src_bucket}/#{src_key}")
  puts "  ✅ 成功 耗时 #{(Time.now - t).round(2)} 秒"
rescue => e
  puts "  ❌ 失败 #{e.class}: #{e.message.to_s[0, 200]}"
end
puts

# [2] download + upload（跨地域，经过服务器）
puts "[2] download+upload 跨地域复制"
begin
  require 'tempfile'
  hz = Aliyun::OSS::Client.new(endpoint: HZ_ENDPOINT, access_key_id: MAIN_ID, access_key_secret: MAIN_SECRET)
  hk = Aliyun::OSS::Client.new(endpoint: HK_ENDPOINT, access_key_id: MAIN_ID, access_key_secret: MAIN_SECRET)

  tmp = Tempfile.new(['copy_hk', '.bin'])
  tmp_path = tmp.path
  tmp.close

  t0 = Time.now
  hz.get_bucket(src_bucket).get_object(src_key, file: tmp_path)
  t1 = Time.now
  hk.get_bucket(DEST_BUCKET).put_object(dest_key, file: tmp_path)
  t2 = Time.now

  size = File.size(tmp_path)
  puts "  下载 #{(t1 - t0).round(2)} 秒 (#{size} 字节), 上传 #{(t2 - t1).round(2)} 秒, 总 #{(t2 - t0).round(2)} 秒"
  File.delete(tmp_path) if File.exist?(tmp_path)
rescue => e
  puts "  ❌ 失败 #{e.class}: #{e.message.to_s[0, 200]}"
end
