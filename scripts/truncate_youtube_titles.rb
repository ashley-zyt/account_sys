require_relative "../config/environment"

# 批量截断 JianyingTask 表中 youtube 平台 title 超过 99 字符的记录
# 前 99 个字符保留在 title 字段，多余部分存入 description 字段
# 执行: rails runner scripts/truncate_youtube_titles.rb

TITLE_LIMIT = 99

puts "=" * 60
puts "批量截断 JianyingTask YouTube 标题"
puts "title 超过 #{TITLE_LIMIT} 字符 → 前 #{TITLE_LIMIT} 字符保留 title，多余存入 description"
puts "=" * 60

# 查找 youtube 平台且 title 超过 99 字符的记录（按字符数过滤）
scope = JianyingTask.where(platform: :youtube).where("CHAR_LENGTH(title) > ?", TITLE_LIMIT)

total_youtube = JianyingTask.where(platform: :youtube).count
need_update = scope.count

puts "YouTube 记录总数: #{total_youtube}"
puts "需要截断的记录数: #{need_update}"

if need_update == 0
  puts "没有需要截断的数据，脚本退出"
  exit 0
end

# 显示示例
sample = scope.order(:id).limit(5).pluck(:id, :title)
puts "\n示例记录（前5条）:"
sample.each do |id, title|
  puts "  ID #{id}: #{title.length} 字符 → title(#{TITLE_LIMIT}) + description(#{title.length - TITLE_LIMIT})"
end

# 确认操作
print "\n确认执行？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == "y"
  puts "已取消操作"
  exit 0
end

# 执行批量更新
updated = 0
skipped = 0
failed = 0

scope.find_each(batch_size: 100) do |task|
  begin
    title = task.title.to_s.strip
    if title.length > TITLE_LIMIT
      excess = title[TITLE_LIMIT..]
      task.update!(
        title: title[0...TITLE_LIMIT],
        description: excess
      )
      updated += 1
    else
      # strip 后不超限（原始可能有首尾空格），跳过
      skipped += 1
    end
    print "\r进度: #{updated + skipped + failed}/#{need_update}"
  rescue => e
    failed += 1
    puts "\n任务 ID #{task.id} 更新失败: #{e.message}"
  end
end

puts "\n"
puts "=" * 60
puts "截断完成！"
puts "成功截断: #{updated} 条"
puts "跳过(strip后不超限): #{skipped} 条"
puts "更新失败: #{failed} 条"
puts "=" * 60
