# 只读诊断：定位「postforme 失败任务没有写 task_log」的根因
#
# 用法：bundle exec rails runner scripts/diagnose_postforme_task_log.rb
#
# 覆盖三种可能：
#   A. mark_failed 根本没触发（post 失败但轮询器没识别到 success=false）
#   B. mark_failed 触发但内部抛异常（pp 已标 failed，但 task_log 没写、任务没重置）
#   C. 都正常（failed 记录其实有 task_log，只是用户没看到）

puts "=" * 78
puts "一、postforme_posts 状态分布"
puts "=" * 78
PostformePost.group(:status).count.sort.each { |k, v| puts "  #{k}: #{v}" }

puts
puts "=" * 78
puts "二、failed 记录 → 是否写了 task_log + 任务是否被重置"
puts "=" * 78
failed = PostformePost.where(status: :failed)
if failed.none?
  puts "  （无 failed 记录）"
else
  puts format("  %-24s %-20s %-12s %-10s %s", "post_id", "task", "task状态", "task_log", "说明")
  failed.each do |pp|
    task = pp.task
    uuid = task&.task_uuid
    log_count = uuid.present? ? TaskLog.where(task_uuid: uuid).count : 0
    note = if log_count.zero?
             "❌ 没写 task_log（走断点 B）"
           else
             "✅ 有 task_log（可能只是没看到）"
           end
    task_status = task&.status.to_s.presence || "任务不存在"
    puts format("  %-24s %-20s %-12s %-10d %s",
                pp.post_id, "#{pp.task_type}##{pp.task_id}", task_status, log_count, note)
  end
end

puts
puts "=" * 78
puts "三、processing 记录（可能实际已失败，但轮询器没识别）"
puts "=" * 78
processing = PostformePost.where(status: :processing).where.not(post_id: nil)
if processing.none?
  puts "  （无 processing 记录）"
else
  processing.each do |pp|
    puts format("  post_id=%s task=%s##%s 提交于=%s",
                pp.post_id, pp.task_type, pp.task_id, pp.created_at&.strftime("%m-%d %H:%M"))
  end
end

puts
puts "=" * 78
puts "四、抽查 processing 记录的 post_result 原始返回（看 success 字段真实值）"
puts "=" * 78
sample = processing.first
if sample.nil?
  puts "  （无 processing 记录可抽查）"
else
  resp = PostformeApi.post_result(post_id: sample.post_id)
  puts "  HTTP code = #{resp[:code]}"
  puts "  body      = #{resp[:body].inspect}"
  items = PostformeApi.items(resp)
  puts "  items 条数 = #{items.size}"
  items.each_with_index do |r, i|
    puts "    [#{i}] success=#{r['success'].inspect} error=#{r['error'].inspect} post_id=#{r['post_id'].inspect}"
  end
end

puts
puts "=" * 78
puts "五、结论提示"
puts "=" * 78
puts "  - 若「二」里有 failed 但 task_log=0 → 断点 B：mark_failed 内部抛异常被 rescue 吞了，"
puts "    去看 log/postforme_status_poller.log 里有没有「轮询发布异常: xxx」拿具体异常。"
puts "  - 若「三」里有 processing 且「四」显示 success=false 或 error 非空 → 断点 A："
puts "    轮询器没识别到失败，任务卡 processing，不会写 task_log。"
puts "  - 若「四」里 success 字段是 nil/字符串/其它类型（不是布尔 false）→ 判断条件不匹配。"
