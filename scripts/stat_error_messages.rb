# 统计系统中所有失败任务的错误信息分布
#
# 运行：bundle exec rails runner scripts/stat_error_messages.rb
#
# 用途：帮助人工梳理「错误信息 → 中文提示」的映射关系。
#       输出每种错误文本出现的次数、最近出现时间，按次数降序，
#       供你判断哪些错误需要翻译成可操作的中文提示。
#
# 提示：若某条 error_msg 里含动态内容（任务ID/UUID/时间戳等），
#       会导致分组碎片化——看到这类错误时，可先人工归一化前缀再建映射。

scope    = TaskLog.failed.where.not(error_msg: [nil, ""])
counts   = scope.group(:error_msg).count
last_ats = scope.group(:error_msg).maximum(:created_at)

puts "===== 失败任务错误信息统计 ====="
puts "失败日志总数: #{TaskLog.failed.count}"
puts "不同错误信息种类: #{counts.size}"
puts "=" * 78

counts.sort_by { |_, c| -c }.first(200).each_with_index do |(msg, cnt), i|
  text = msg.to_s.strip
  text = "#{text[0, 78]}..." if text.length > 78
  last_at = last_ats[msg]
  puts sprintf("%3d. [%6d 次] %s", i + 1, cnt, text)
  puts "     最近出现: #{last_at&.strftime('%Y-%m-%d %H:%M')}"
end

puts "=" * 78
puts "完成（共展示 #{[counts.size, 200].min} 种，其余种类可调整 limit 查看）"
