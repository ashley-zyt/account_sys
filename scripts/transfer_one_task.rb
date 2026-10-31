# ===== 先转存一条历史任务验证，确认无误后再批量 =====
#
# 用法（生产服务器 Ruby 2.7.2）：
#   bundle exec rails runner scripts/transfer_one_task.rb
#   指定源 bucket：
#   bundle exec rails runner scripts/transfer_one_task.rb jianying-rd
#
# 从新到旧找一条「源对象确实存在」的旧任务，转存到新 bucket 并换链，打印结果。

src = ARGV[0] || 'jianying-rd'
model_name = {
  'huasheng-ld'   => 'HuashengTask',
  'jianying-rd'   => 'JianyingTask',
  'notebooklm-ld' => 'NotebooklmTask'
}[src] || 'JianyingTask'

model = model_name.constantize
src_client = OssTransfer.oss_client(*OssTransfer.source_credentials)

# 从新到旧找第一条源对象确实存在的任务（最多看 50 条）
task = model.where("oss_url LIKE ?", "%#{src}.oss-%")
            .where.not(full_oss_url: [nil, ''])
            .order(id: :desc)
            .limit(50)
            .to_a
            .find { |t|
  src_client.get_bucket(src).object_exists?(t.full_oss_url.to_s.strip.sub(%r{^/}, ''))
}

if task.nil?
  puts "未找到源对象存在的旧任务（#{src}）"
else
  key = task.full_oss_url.to_s.strip.sub(%r{^/}, '')
  puts "任务 ##{task.id}  key=#{key}"
  result = OssTransfer.transfer(src, key)

  if result
    new_key, new_url = result
    task.update_columns(oss_url: new_url, full_oss_url: new_key, updated_at: Time.current)
    puts "✅ 转存成功"
    puts "  new_key = #{new_key}"
    puts "  new_url = #{new_url}"
  else
    puts "❌ 转存失败（看日志 [OssTransfer] 转存失败）"
  end
end
