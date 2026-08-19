# frozen_string_literal: true

# 批量重置花生视频储备关键词状态为"未启动"(status=0)
# 指定 ID 范围: 15 到 26
# 执行: rails runner scripts/reset_huasheng_keywords.rb

require 'benchmark'

puts "=" * 60
puts "批量重置花生视频储备关键词状态脚本"
puts "ID 范围: 15 ~ 26"
puts "=" * 60

ids = [104,105]

count = HuashengKeyword.where(id: ids).count
puts "范围内记录数: #{count}"

if count == 0
  puts "没有需要更新的数据，脚本退出"
  exit 0
end

print "确认将 ID 15~26 的数据状态更新为未启动？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == 'y'
  puts "已取消操作"
  exit 0
end

time = Benchmark.measure do
  updated = HuashengKeyword.where(id: ids).update_all(
    status: 0,
    task_id: nil,
    result_data: nil,
    updated_at: Time.current
  )
  puts "成功更新 #{updated} 条记录"
end

puts "耗时: #{time.real.round(2)} 秒"

puts "=" * 60
puts "重置完成！"
puts "=" * 60
