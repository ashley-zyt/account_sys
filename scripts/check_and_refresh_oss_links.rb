# ===== 检查 + 清理失效 OSS 链接 / 续期有效链接（preview / confirm 两阶段）=====
#
# 逻辑：
#   1. 扫描 7 张表（6 张资源队列 + MoveVideo 源视频）的 OSS 链接
#   2. 用 OSS SDK object_exists? 检查源文件是否存在
#   3. 不存在 → 记入「失效」，confirm 时删除记录
#   4. 存在   → 记入「可续期」，confirm 时重新生成 1 年签名 URL 写回
#
# 用法：
#   预览（只扫描，不改任何数据）：
#     bundle exec rails runner scripts/check_and_refresh_oss_links.rb
#   执行（删除失效 + 续期有效）：
#     bundle exec rails runner scripts/check_and_refresh_oss_links.rb confirm
#
# 注意：只删库（资源任务/视频记录），不动 OSS 文件、不动 task_log / TaskAssignment / browser_task_record。

confirm = (ARGV[0] == 'confirm')

results = OssLinkChecker.run(confirm: confirm)

puts '==== OSS 链接检查结果 ===='
puts "失效（文件不存在，将被清除）：#{results[:missing].size} 条"
puts "可续期（文件存在）：#{results[:refreshable].size} 条"
puts "跳过（无法解析 bucket/key）：#{results[:skipped].size} 条"
puts "检查异常：#{results[:error].size} 条"
puts

if confirm
  puts "已删除失效记录：#{results[:deleted]} 条"
  puts "已续期：#{results[:refreshed]} 条"
  puts
end

# 失效按表分布
if results[:missing].any?
  puts '失效（按表分布）：'
  results[:missing].group_by { |e| e[:model] }
         .sort_by { |_k, v| -v.size }
         .each { |k, v| puts "  #{k}: #{v.size}" }
  puts
  puts '失效清单（前 50 条）：'
  results[:missing].first(50).each { |e| puts "  #{e[:model]}##{e[:id]} | #{e[:bucket]}/#{e[:key][0, 60]}" }
  puts "  ...（共 #{results[:missing].size} 条）" if results[:missing].size > 50
  puts
end

# 可续期按表分布
if results[:refreshable].any?
  puts '可续期（按表分布）：'
  results[:refreshable].group_by { |e| e[:model] }
         .sort_by { |_k, v| -v.size }
         .each { |k, v| puts "  #{k}: #{v.size}" }
  puts
end

# 跳过 / 异常
if results[:skipped].any?
  puts '跳过（前 20 条，多为 URL 字段为空或非 OSS 链接）：'
  results[:skipped].first(20).each { |e| puts "  #{e[:model]}##{e[:id]}" }
  puts "  ...（共 #{results[:skipped].size} 条）"
  puts
end

if results[:error].any?
  puts '检查异常（前 20 条，多为 bucket 不存在/网络错误，已保守处理未误删）：'
  results[:error].first(20).each { |e| puts "  #{e[:model]}##{e[:id]}: #{e[:reason][0, 80]}" }
  puts
end

unless confirm
  puts '⚠️ 以上为预览，未做任何改动。确认无误后执行：'
  puts '  bundle exec rails runner scripts/check_and_refresh_oss_links.rb confirm'
end
