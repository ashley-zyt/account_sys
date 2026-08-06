require_relative "../config/environment"

# 批量修正 JianyingTask 表的 theme 字段，为所有未带前缀的主题添加 "剪映-" 前缀
# 执行: ruby scripts/add_jianying_prefix_to_themes.rb
#   或: rails runner scripts/add_jianying_prefix_to_themes.rb

PREFIX = "剪映-".freeze

puts "=" * 60
puts "批量修正 JianyingTask 主题前缀"
puts "为所有 theme 字段添加 '#{PREFIX}' 前缀"
puts "=" * 60

# 需要更新的记录：theme 非空且不以 "剪映-" 开头
scope = JianyingTask.where("theme IS NOT NULL AND theme != '' AND theme NOT LIKE '#{PREFIX}%'")

total = JianyingTask.count
need_update = scope.count

puts "总记录数: #{total}"
puts "需要添加前缀的记录数: #{need_update}"

if need_update == 0
  puts "没有需要更新的数据，脚本退出"
  exit 0
end

# 显示将受影响的主题列表
themes = scope.distinct.pluck(:theme)
puts "\n将更新以下主题:"
themes.each { |t| puts "  #{t}  →  #{PREFIX}#{t}" }

# 确认操作
print "\n确认执行？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == "y"
  puts "已取消操作"
  exit 0
end

# 执行批量更新（update_all 跳过回调/校验，直接 SQL 更新）
affected = scope.update_all("theme = CONCAT('#{PREFIX}', theme), updated_at = NOW()")

puts "\n更新完成! 影响记录数: #{affected}"

# 验证结果
remaining = JianyingTask.where("theme IS NOT NULL AND theme != '' AND theme NOT LIKE '#{PREFIX}%'").count
puts "剩余未添加前缀的记录数: #{remaining}"

puts "=" * 60
puts "修正完成！"
puts "=" * 60
