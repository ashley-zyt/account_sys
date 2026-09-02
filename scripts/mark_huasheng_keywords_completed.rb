# frozen_string_literal: true

# 重新推送「花生视频-抖音号视频号」主题下已推送的关键词
#   1. 筛选 theme=花生视频-抖音号视频号、status=执行完成、且已推送(pushed=true) 的关键词
#   2. 删除其在 huasheng_tasks 表中对应的任务数据
#   3. 调用 HuashengTask.create_from_huasheng_keyword! 重新推送生成任务
# 执行: rails runner scripts/mark_huasheng_keywords_completed.rb

require 'benchmark'

THEME = "花生视频-抖音号视频号".freeze

puts "=" * 60
puts "重新推送主题「#{THEME}」的已推送关键词"
puts "=" * 60

keywords = HuashengKeyword.where(theme: THEME, status: 3, pushed: true).order(id: :asc)
total = keywords.size
puts "符合条件的已推送关键词: #{total} 条"

if total == 0
  puts "没有需要处理的记录，脚本退出"
  exit 0
end

keywords.each do |kw|
  puts "  ID=#{kw.id} key=#{kw.keyword}"
end

print "确认删除以上关键词对应的 huasheng_tasks 并重新推送？(y/N): "
answer = STDIN.gets&.strip
unless answer&.downcase == 'y'
  puts "已取消操作"
  exit 0
end

time = Benchmark.measure do
  deleted = 0
  success = 0
  failed = 0

  keywords.each do |kw|
    # 1. 删除该关键词对应的全部花生任务
    tasks = HuashengTask.where(huasheng_keyword_id: kw.id)
    removed = tasks.count
    tasks.delete_all
    deleted += removed
    puts "  ID=#{kw.id} key=#{kw.keyword}: 删除任务 #{removed} 条"

    # 2. 重新推送
    begin
      created, err = HuashengTask.create_from_huasheng_keyword!(kw)
      if created > 0
        success += 1
        puts "    => 重新推送 #{created} 条任务成功"
      else
        failed += 1
        puts "    => 重新推送失败: #{err}"
      end
    rescue => e
      failed += 1
      puts "    => 重新推送异常: #{e.class} #{e.message}"
    end
  end

  puts ""
  puts "处理完成：删除任务 #{deleted} 条，重新推送成功 #{success} 条，失败 #{failed} 条"
end

puts "耗时: #{time.real.round(2)} 秒"
puts "=" * 60
puts "完成！"
puts "=" * 60