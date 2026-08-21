# frozen_string_literal: true

# 批量将指定花生视频储备关键词状态更新为"执行完成"(status=3)
# 只更新 status 和 updated_at，其他字段保持不变
# 执行: rails runner scripts/mark_huasheng_keywords_completed.rb

require 'benchmark'

puts "=" * 60
puts "批量更新花生视频储备关键词状态为执行完成"
puts "=" * 60

# 修改这里的 ID 列表
ids = [144]

count = HuashengKeyword.where(id: ids).count
puts "指定 ID 记录数: #{count}"

if count == 0
  puts "没有需要更新的数据，脚本退出"
  exit 0
end

# 显示当前状态
HuashengKeyword.where(id: ids).each do |kw|
  puts "  ID #{kw.id}: #{kw.keyword} (当前状态: #{kw.status_name})"
end

print "确认将这些记录状态更新为"执行完成"？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == 'y'
  puts "已取消操作"
  exit 0
end

time = Benchmark.measure do
  updated = HuashengKeyword.where(id: ids).update_all(
    status: 3,
    updated_at: Time.current
  )
  puts "成功更新 #{updated} 条记录"
end

puts "耗时: #{time.real.round(2)} 秒"

puts "=" * 60
puts "更新完成！"
puts "=" * 60