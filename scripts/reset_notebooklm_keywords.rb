# frozen_string_literal: true

# 批量重置 NotebookLM 视频储备关键词状态为"未启动"(status=0)
# 执行: rails runner scripts/reset_notebooklm_keywords.rb
#
# 使用方式:
#   1. 编辑下面的 ids 数组，指定要重置的关键词 ID
#   2. 运行: rails runner scripts/reset_notebooklm_keywords.rb
#   3. 确认后执行

require 'benchmark'

puts "=" * 60
puts "批量重置 NotebookLM 视频储备关键词状态脚本"
puts "=" * 60

# 在此处指定要重置的 ID 列表
ids = [1，2]

if ids.empty?
  puts "请在脚本中指定要重置的 ID 列表"
  puts "例如: ids = [1, 2, 3]"
  exit 1
end

count = NotebooklmKeyword.where(id: ids).count
puts "ID 列表: #{ids}"
puts "范围内记录数: #{count}"

if count == 0
  puts "没有需要更新的数据，脚本退出"
  exit 0
end

print "确认将以上 #{count} 条数据的状态更新为未启动？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == 'y'
  puts "已取消操作"
  exit 0
end

time = Benchmark.measure do
  updated = NotebooklmKeyword.where(id: ids).update_all(
    status: 0,
    task_id: nil,
    result_data: nil,
    pushed: false,
    updated_at: Time.current
  )
  puts "成功更新 #{updated} 条记录"
end

puts "耗时: #{time.real.round(2)} 秒"

puts "=" * 60
puts "重置完成！"
puts "=" * 60