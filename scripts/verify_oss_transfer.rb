# ===== 验证转存：自动匹配「源对象确实存在」的任务测试 =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/verify_oss_transfer.rb
#
# 逻辑：
#   1. list 源 bucket 前 200 个对象 key
#   2. 找库里 full_oss_url 与这批 key 有交集的任务
#   3. 用该任务真实转存，并测发布兜底 ensure_transferred

puts "===== 转存功能验证 ====="
puts

src_client = OssTransfer.oss_client(*OssTransfer.source_credentials)

old_defs = [
  ['HuashengTask',   'huasheng-ld'],
  ['JianyingTask',   'jianying-rd'],
  ['NotebooklmTask', 'notebooklm-ld']
]

old_defs.each do |name, src|
  model = name.constantize
  puts "[#{name}]"

  begin
    b = src_client.get_bucket(src)
    list = b.list_objects(max_keys: 200)
    page = list.respond_to?(:objects) ? list.objects : list.to_a
    existing_keys = page.map(&:key)
  rescue => e
    puts "  ❌ 列源 bucket 失败：#{e.class}: #{e.message[0, 100]}"
    puts
    next
  end

  task = model.where(full_oss_url: existing_keys).first
  if task.nil?
    puts "  库里的 full_oss_url 与源 bucket 前 #{existing_keys.size} 个对象无交集"
    puts
    next
  end

  key = task.full_oss_url.to_s.strip.sub(%r{^/}, '')
  puts "  匹配到任务 ##{task.id}，key=#{key}（源对象存在）"

  result = OssTransfer.transfer(src, key)
  if result
    puts "  ✅ OssTransfer.transfer 成功 → #{result.last[0, 100]}"
  else
    puts "  ❌ OssTransfer.transfer 失败"
  end
  puts
end

# ---------- 发布兜底 ensure_transferred ----------
puts "[发布兜底 ensure_transferred]"
huasheng = HuashengTask.where("oss_url LIKE ?", "%huasheng-ld.oss-%").where.not(full_oss_url: [nil, '']).first
if huasheng.nil?
  puts "  无旧 bucket 的 HuashengTask，跳过"
else
  before = huasheng.oss_url.to_s
  ok = PublishScheduler.ensure_transferred(huasheng)
  huasheng.reload
  after = huasheng.oss_url.to_s
  puts "  HuashengTask##{huasheng.id}"
  puts "    转存前: #{before[0, 100]}"
  puts "    转存后: #{after[0, 100]}"
  puts "    结果  : #{before != after ? '✅ 已换链到新 bucket' : '❌ 未换链'}"
end
puts

puts "===== 验证完成 ====="
