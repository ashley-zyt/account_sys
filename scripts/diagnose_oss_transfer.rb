# ===== 诊断 OSS 转存失败的具体原因 =====
#
# 逐层测试并捕获异常，定位转存在哪一步失败：
#   源凭证 / 源 bucket 读 / 目标 bucket 存在性 / 目标写权限 / 完整转存
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/diagnose_oss_transfer.rb

def show(name, ok, msg = nil)
  mark = ok ? '✅' : '❌'
  puts "  #{mark} #{name}#{msg ? "：#{msg}" : ''}"
end

puts "===== OSS 转存诊断 ====="
puts

# ---------- A. 源凭证对比 ----------
puts "[A] 源凭证（TWO 账号）"
hardcoded_id = OssTransfer::SOURCE_ACCESS_KEY_ID
two_id = ENV['ALIYUN_ACCESS_TWO_KEY_ID']
puts "  硬编码源 key 前4位      : #{hardcoded_id.to_s[0, 4]}****"
puts "  ENV TWO key 是否配置    : #{two_id.present? ? '已配置 ✓' : '❌ 未配置'}"
puts "  两者是否相同            : #{hardcoded_id == two_id}"
puts "  （若不相同，说明源 bucket 应该用 ENV ALIYUN_ACCESS_TWO_KEY_ID 访问）"
puts

# ---------- B. 源 bucket 读访问（硬编码凭证） ----------
puts "[B] 源 bucket 读访问（硬编码凭证 #{hardcoded_id.to_s[0, 4]}****）"
src_client = OssTransfer.oss_client(*OssTransfer.source_credentials)
{
  'huasheng-ld'   => 'video/video_1786983048.mp4',
  'jianying-rd'   => 'video/task_E0002_20260715_203612.mp4',
  'notebooklm-ld' => 'video/trimmed_clean_d549a93a-f3ac-4bf8-b9da-4583238a5a83.mp4'
}.each do |bucket, key|
  begin
    b = src_client.get_bucket(bucket)
    exists = b.object_exists?(key)
    show("#{bucket} 读访问", true, "object_exists?=#{exists}")
  rescue => e
    show("#{bucket} 读访问", false, "#{e.class}: #{e.message[0, 120]}")
  end
end
puts

# ---------- C. 目标 bucket 访问（主账号凭证） ----------
puts "[C] 目标 bucket 访问（主账号 ENV）"
dst_client = OssTransfer.oss_client(*OssTransfer.dest_credentials)
{
  'huasheng-ld-videos'   => 'video/video_1786983048.mp4',
  'jianying-rd-videos'   => 'video/task_E0002_20260715_203612.mp4',
  'notebooklm-ld-videos' => 'video/trimmed_clean_d549a93a-f3ac-4bf8-b9da-4583238a5a83.mp4'
}.each do |bucket, key|
  begin
    b = dst_client.get_bucket(bucket)
    exists = b.object_exists?(key)
    show("#{bucket} 访问", true, "object_exists?=#{exists}（不存在属正常，未转存过）")
  rescue => e
    show("#{bucket} 访问", false, "#{e.class}: #{e.message[0, 120]}")
  end
end
puts

# ---------- D. 完整转存（捕获原始异常） ----------
puts "[D] 完整转存（直接调用底层，捕获原始异常）"
begin
  src = src_client.get_bucket('huasheng-ld')
  dst = dst_client.get_bucket('huasheng-ld-videos')
  key = 'video/video_1786983048.mp4'
  if dst.object_exists?(key)
    puts "  目标已存在，跳过上传（幂等）"
  else
    obj = src.get_object(key)
    content = obj.respond_to?(:read) ? obj.read : obj.body
    puts "  读源成功，size=#{content.to_s.bytesize} 字节"
    dst.put_object(key, content: content)
    puts "  写目标成功 ✅"
  end
rescue => e
  puts "  ❌ 转存异常：#{e.class}: #{e.message}"
  puts "  #{e.backtrace.first(5).join("\n")}"
end
puts

puts "===== 诊断完成 ====="
