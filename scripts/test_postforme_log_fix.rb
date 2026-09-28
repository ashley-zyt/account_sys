# 测试 postforme 失败日志修复 + 回填历史缺失日志
#
# 用法：
#   bundle exec rails runner scripts/test_postforme_log_fix.rb            # 预览 + 单元验证（不改数据）
#   bundle exec rails runner scripts/test_postforme_log_fix.rb confirm    # 执行：真正回填历史缺失日志
#
# 说明：
#   历史 failed 记录里的 pp.error_msg 是修复前 mark_failed 存下的（可能是 hash 字符串、含非法字节），
#   现在能成功写进 task_log，就证明 safe_utf8 清洗 + 友好提取生效了。

puts "=" * 72
puts "一、safe_utf8 单元验证"
puts "=" * 72
puts "  正常中文: #{TaskReportHelper.safe_utf8('正常').inspect}"

bad = "bad\xFFbyte".b   # 二进制非法字节
cleaned = TaskReportHelper.safe_utf8(bad)
puts "  非法字节清洗后: #{cleaned.inspect}"
puts "  → valid_encoding? = #{cleaned.valid_encoding?}"

nil_result = TaskReportHelper.safe_utf8(nil)
puts "  nil 输入: #{nil_result.inspect}"

puts
puts "=" * 72
puts "二、extract_error_message 单元验证"
puts "=" * 72
puts "  error.message:   #{PostformeStatusPoller.extract_error_message({'error' => {'message' => '账号被封'}}).inspect}"
puts "  error.code:      #{PostformeStatusPoller.extract_error_message({'error' => {'code' => 'E001'}}).inspect}"
puts "  error 为 nil:    #{PostformeStatusPoller.extract_error_message({'error' => nil}).inspect}"
puts "  error 为 hash 无 message/code: #{PostformeStatusPoller.extract_error_message({'error' => {'foo' => 'bar'}}).inspect}"

puts
puts "=" * 72
puts "三、历史 failed 缺失 task_log 回填（#{ARGV[0] == 'confirm' ? '执行' : '预览'}）"
puts "=" * 72
confirm = ARGV[0] == 'confirm'
count = 0

PostformePost.where(status: :failed).find_each do |pp|
  task = pp.task
  next unless task
  next if TaskLog.where(task_uuid: task.task_uuid).exists?

  count += 1
  puts "  缺失: #{pp.task_type}##{pp.task_id} (post_id=#{pp.post_id})"
  puts "        error=#{pp.error_msg.to_s.truncate(60)}"

  if confirm
    # 任务可能已被重置 pending（account_id 已清空），归属从 TaskAssignment 补
    snap = TaskAssignment.snapshot_for(task.task_uuid)
    begin
      TaskReportHelper.create_task_log(task, 'error', snap&.account_id, snap&.browser_id, pp.error_msg)
      puts "        → 已补写 task_log"
    rescue => e
      puts "        → 补写失败: #{e.class} #{e.message}"
    end
  end
end

puts
puts "  共 #{count} 条缺失日志#{confirm ? '（已补写）' : '（预览，加 confirm 参数执行回填）'}"

puts
puts "=" * 72
puts "四、结论提示"
puts "=" * 72
puts "  - 若「一」「二」输出正常（非法字节被清洗、error.message 被提取出来），修复逻辑 OK。"
puts "  - 若「三」confirm 后没有「补写失败」，说明 create_task_log 现在能正常写失败日志。"
puts "  - 重启 Rails 后，新的失败任务会自动写 task_log；观察 log/postforme_status_poller.log"
puts "    里是否还有「写失败 task_log 异常」，没有就说明修复生效。"
