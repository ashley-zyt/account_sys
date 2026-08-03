# frozen_string_literal: true

# 批量重置 RedNoteKeyword 表中失败状态的数据为"未启动"
# 执行: rails runner scripts/reset_failed_red_note_keywords.rb
# require_relative "../config/environment"
require 'benchmark'

puts "=" * 60
puts "批量重置小红书关键词失败状态脚本"
puts "=" * 60

# 统计需要更新的数据
failed_count = RedNoteKeyword.where(status: 4).count
puts "待重置的失败记录数: #{failed_count}"

if failed_count == 0
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
  # 先清空 task_id 和 result_data
  updated = RedNoteKeyword.where(status: 4).update_all(
    status: 0,
    task_id: nil,
    result_data: nil,
    updated_at: Time.current
  )
  puts "成功更新 #{updated} 条记录"
end

puts "耗时: #{time.real.round(2)} 秒"

# 验证结果
remaining_failed = RedNoteKeyword.where(status: 4).count
reset_count = RedNoteKeyword.where(status: 0).count
puts "剩余失败记录数: #{remaining_failed}"
puts "当前未启动记录数: #{reset_count}"

puts "=" * 60
puts "重置完成！"
puts "=" * 60
