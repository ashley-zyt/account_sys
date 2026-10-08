# -*- coding: utf-8 -*-
# 检查「最近发布失败超过阈值次数」的资源队列任务，置为 failed 终态（不再重新分配）。
#
# 背景：failure_count 字段是后来才加的，历史资源的失败次数只存在于 task_logs 中
# （每次发布失败写一条 status=failed 的记录，task_uuid 关联到对应任务）。
# 本脚本按 task_uuid 聚合 task_logs 的 failed 记录，把「失败次数超过阈值」且仍可重试
# （pending / waiting_publish）的任务置为 failed，后续交给 StorageCleaner 统一清理。
#
# 用法：
#   bundle exec rails runner scripts/mark_overfailed_resources.rb              # 预览（只统计，不改动）
#   bundle exec rails runner scripts/mark_overfailed_resources.rb confirm      # 执行（阈值 6）
#   bundle exec rails runner scripts/mark_overfailed_resources.rb 8 confirm    # 执行（阈值 8）
#   bundle exec rails runner scripts/mark_overfailed_resources.rb 6 30 confirm # 阈值 6、只统计最近 30 天
#
# 参数（顺序不限）：
#   数字     第一个数字 = 失败次数阈值（默认 6，严格「超过」即 >= 阈值+1）；第二个数字 = 只统计最近 N 天（可选）
#   confirm  加上才真正执行；不加只预览
#
# 注意：只动 pending / waiting_publish 状态；executing / success / failed 一律不动。

confirm   = ARGV.include?('confirm')
numeric   = ARGV.reject { |a| a == 'confirm' }.map(&:to_i)
threshold = numeric[0] || 6
days      = numeric[1] if numeric[1] && numeric[1] > 0

puts "===== 标记「发布失败超过 #{threshold} 次」的资源（#{confirm ? '执行' : '预览'}）====="
puts "统计范围：#{days ? "最近 #{days} 天" : '全部历史'} 的失败记录"
puts ""

# 1) 按 task_uuid 聚合 failed 日志，只保留失败次数超过阈值的任务
failed_scope = TaskLog.where(status: :failed)
failed_scope = failed_scope.where("run_at >= ?", days.days.ago) if days

over_uuids = failed_scope.group(:task_uuid).having("COUNT(*) > ?", threshold).count
# over_uuids => { task_uuid => 失败次数 }

if over_uuids.empty?
  puts "没有失败次数超过 #{threshold} 次的资源，无需处理。"
  exit
end

puts "失败超过 #{threshold} 次的 task_uuid 共 #{over_uuids.size} 个："
over_uuids.sort_by { |_uuid, c| -c }.each { |uuid, c| puts format("  %-40s %d 次", uuid, c) }
puts ""

# 2) 遍历各资源队列，把仍可重试的任务置为 failed
retryable = %w[pending waiting_publish]
total = 0

WorkMode.resource_modes.each do |mode|
  model = mode.task_model_class
  rows  = model.where(task_uuid: over_uuids.keys, status: retryable).to_a
  next if rows.empty?

  puts "【#{mode.name}】命中 #{rows.size} 条"
  rows.each do |task|
    count = over_uuids[task.task_uuid]
    if confirm
      attrs = {
        status:     model.statuses[:failed],
        account_id: nil,
        browser_id: nil,
        start_at:   nil,
        error_msg:  "连续发布失败 #{count} 次，脚本标记为失败",
        updated_at: Time.current
      }
      attrs[:failure_count] = count if model.column_names.include?('failure_count')
      task.update_columns(attrs)
      TaskAssignment.release!(task.task_uuid, "连续发布失败 #{count} 次，脚本标记为失败")
      puts format("  [已标记] #%d %s 失败 %d 次", task.id, task.task_uuid, count)
    else
      puts format("  [预览]   #%d %s 失败 %d 次", task.id, task.task_uuid, count)
    end
    total += 1
  end
end

puts ""
if confirm
  puts "完成：共标记 #{total} 条资源为 failed。"
else
  puts "这是预览，未做任何改动。确认无误后执行："
  puts "  bundle exec rails runner scripts/mark_overfailed_resources.rb confirm"
end
