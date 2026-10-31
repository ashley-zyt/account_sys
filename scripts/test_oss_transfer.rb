# ===== 模拟测试 OSS 转存功能 =====
#
# 覆盖：
#   1. 主账号凭证（目标 bucket 写入需要）是否配置
#   2. OssTransfer URL 解析（bucket_from_url / key_from_url）
#   3. 源 bucket 识别（是否命中 BUCKET_MAP 映射）
#   4. 真实转存：从库里取一条旧 bucket 任务，实际转存到新 bucket
#   5. 发布兜底 PublishScheduler.ensure_transferred 是否能把旧任务换链
#
# 用法（生产服务器 Ruby 2.7.2 环境）：
#   bundle exec rails runner scripts/test_oss_transfer.rb
#
# 说明：转存只读源对象、写目标对象，不删除源；目标已存在则跳过上传（幂等）。

puts "===== OSS 转存功能测试 ====="
puts "时间：#{Time.current}"
puts

# ---------- 1. 目标凭证检查 ----------
puts "[1] 主账号凭证检查（目标 bucket 写入需要）"
kid = ENV['ALIYUN_ACCESS_KEY_ID']
sec = ENV['ALIYUN_ACCESS_KEY_SECRET']
puts "  ALIYUN_ACCESS_KEY_ID     : #{kid.present? ? '已配置 ✓' : '❌ 未配置'}"
puts "  ALIYUN_ACCESS_KEY_SECRET : #{sec.present? ? '已配置 ✓' : '❌ 未配置'}"
puts

# ---------- 2. URL 解析测试 ----------
puts "[2] URL 解析测试（纯逻辑，无副作用）"
[
  "https://huasheng-ld.oss-cn-hangzhou.aliyuncs.com/video/abc%20123.mp4?OSSAccessKeyId=xx",
  "https://jianying-rd.oss-cn-hangzhou.aliyuncs.com/S_food/12345.mp4",
  "https://notebooklm-ld.oss-cn-hangzhou.aliyuncs.com/nb/xx.mp4",
  "https://huasheng-ld-videos.oss-cn-hangzhou.aliyuncs.com/video/abc.mp4"
].each do |url|
  b = OssTransfer.bucket_from_url(url)
  k = OssTransfer.key_from_url(url)
  puts "  bucket=#{b.inspect.ljust(20)} key=#{k.inspect}"
end
puts

# ---------- 3. 源 bucket 识别 ----------
puts "[3] 源 bucket 识别（只看是否命中 BUCKET_MAP，不真正转存）"
{
  "https://huasheng-ld.oss-cn-hangzhou.aliyuncs.com/video/x.mp4" => "应命中 huasheng-ld-videos",
  "https://jianying-rd.oss-cn-hangzhou.aliyuncs.com/S/x.mp4"     => "应命中 jianying-rd-videos",
  "https://notebooklm-ld.oss-cn-hangzhou.aliyuncs.com/n/x.mp4"   => "应命中 notebooklm-ld-videos",
  "https://jianying-videos.oss-cn-hangzhou.aliyuncs.com/x.mp4"   => "应跳过（主账号，非源）",
  "https://grok-videos.oss-cn-hangzhou.aliyuncs.com/x.mp4"       => "应跳过（主账号，非源）"
}.each do |url, expect|
  b = OssTransfer.bucket_from_url(url)
  mapped = OssTransfer::BUCKET_MAP[b]
  puts "  #{b.inspect.ljust(16)} → #{mapped ? mapped.inspect : '跳过'}   #{expect}"
end
puts

# ---------- 4. 真实转存测试 ----------
puts "[4] 真实转存测试（从库里取一条旧 bucket 任务，实际转存到新 bucket）"
puts "    只读源对象、写目标对象，不删除源。"
puts

old_defs = [
  ['HuashengTask',   'huasheng-ld'],
  ['JianyingTask',   'jianying-rd'],
  ['NotebooklmTask', 'notebooklm-ld']
]

old_defs.each do |name, src|
  model = name.constantize
  task = model.where("oss_url LIKE ?", "%#{src}.oss-%").where.not(full_oss_url: [nil, '']).first

  if task.nil?
    puts "  #{name}: 无旧 bucket 任务（或 full_oss_url 为空），跳过"
    puts
    next
  end

  key = task.full_oss_url.to_s.strip.sub(%r{^/}, '')
  puts "  #{name}##{task.id}  key=#{key}"
  result = OssTransfer.transfer(src, key)

  if result
    new_key, new_url = result
    puts "    ✅ 转存成功"
    puts "      新 key : #{new_key}"
    puts "      新 URL : #{new_url[0, 110]}"
  else
    puts "    ❌ 转存失败（请查看日志 [OssTransfer] 转存失败 的具体报错）"
  end
  puts
end

# ---------- 5. 发布兜底 ensure_transferred 测试 ----------
puts "[5] 发布兜底 PublishScheduler.ensure_transferred 测试"
huasheng = HuashengTask.where("oss_url LIKE ?", "%huasheng-ld.oss-%").where.not(full_oss_url: [nil, '']).first

if huasheng.nil?
  puts "  无旧 bucket 的 HuashengTask 可测试，跳过"
else
  before_url = huasheng.oss_url.to_s
  puts "  HuashengTask##{huasheng.id}"
  puts "    转存前 oss_url : #{before_url[0, 100]}"
  ok = PublishScheduler.ensure_transferred(huasheng)
  huasheng.reload
  after_url = huasheng.oss_url.to_s
  puts "    转存后 oss_url : #{after_url[0, 100]}"
  changed = before_url != after_url
  puts "    结果           : #{ok || changed ? '✅ 已换链到新 bucket' : '❌ 未换链（转存失败或已新 bucket）'}"
end
puts

puts "===== 测试完成 ====="
