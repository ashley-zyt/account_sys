# frozen_string_literal: true

# 批量重置 RedNoteKeyword 表中待执行状态(status=1)的数据为"未启动"(status=0)
# 执行: rails runner scripts/reset_pending_red_note_keywords.rb
require 'benchmark'

puts "=" * 60
puts "批量重置红书照片关键词待执行状态脚本"
puts "status: 1(待执行) => 0(未启动)"
puts "=" * 60

# 统计需要更新的数据
pending_count = RedNoteKeyword.where(status: 1).count
puts "待重置的待执行记录数: #{pending_count}"

if pending_count == 0
  puts "没有需要重置的数据，脚本退出"
  exit 0
end

# 确认操作
print "确认执行？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == 'y'
  puts "已取消操作"
  exit 0
end

# 执行批量更新
time = Benchmark.measure do
  updated = RedNoteKeyword.where(status: 1).update_all(
    status: 0,
    task_id: nil,
    result_data: nil,
    updated_at: Time.current
  )
  puts "成功更新 #{updated} 条记录"
end

puts "耗时: #{time.real.round(2)} 秒"

# 验证结果
remaining_pending = RedNoteKeyword.where(status: 1).count
reset_count = RedNoteKeyword.where(status: 0).count
puts "剩余待执行记录数: #{remaining_pending}"
puts "当前未启动记录数: #{reset_count}"

puts "=" * 60
puts "重置完成！"
puts "=" * 60