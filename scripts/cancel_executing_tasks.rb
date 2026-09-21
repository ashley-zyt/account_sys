# -*- coding: utf-8 -*-
# 把指定平台「执行中(executing)」的发布任务重置回 pending（取消执行、重新排队）。
# 与机器端 POST /tasks/clear?type={platform}_publish&status=running,queued 配套使用：
#   机器端负责中断 goroutine 并抑制回调；本脚本负责把 account_sys 里卡在
#   executing 的任务回滚到 pending，避免它们一直停在「执行中」等 45 分钟超时兜底。
#
# 用法：
#   bundle exec rails runner scripts/cancel_executing_tasks.rb tiktok            # 预览（只统计）
#   bundle exec rails runner scripts/cancel_executing_tasks.rb tiktok confirm    # 执行
#
# 参数：
#   <platform>  目标平台：facebook / twitter / tiktok / youtube / instagram（必填）
#   confirm     加上才真正重置；不加只预览
#
# 效果：status=pending、account_id=nil、browser_id=nil、start_at=nil、error_msg=nil
# 注意：只动 executing 状态；success / failed / pending / waiting_publish 一律不动。

platform = ARGV[0].to_s.strip
confirm  = ARGV[1] == 'confirm'

if platform.empty?
  puts "用法："
  puts "  bundle exec rails runner scripts/cancel_executing_tasks.rb <platform> [confirm]"
  puts "  platform: facebook / twitter / tiktok / youtube / instagram"
  puts "  confirm:  加 confirm 才真正重置，否则只预览"
  exit 1
end

models = WorkMode.publishable_modes
                 .map(&:task_model_class)
                 .select { |m| m.respond_to?(:platforms) && m.statuses.key?('executing') }

puts "===== 取消 #{platform} 执行中任务（#{confirm ? '执行' : '预览'}）====="
puts ""

rows = []
total = 0
models.each do |model|
  count = model.where(platform: platform, status: :executing).count
  rows << [model, count]
  total += count
  puts format("  %-22s executing %d 条", model.name, count)
end
puts ""
puts "合计：#{total} 条 executing"

unless confirm
  puts ""
  puts "这是预览，未做任何修改。确认无误后执行："
  puts "  bundle exec rails runner scripts/cancel_executing_tasks.rb #{platform} confirm"
  exit
end

puts ""
puts "===== 开始执行 ====="

done = 0
rows.each do |model, count|
  next if count.zero?
  n = model.where(platform: platform, status: :executing)
           .update_all(
             status: :pending,
             account_id: nil,
             browser_id: nil,
             start_at: nil,
             error_msg: nil,
             updated_at: Time.current
           )
  done += n
  puts format("  %-22s 已重置 %d 条 → pending", model.name, n)
end

puts ""
puts "===== 完成 ====="
puts "已把 #{platform} 执行中任务重置回 pending 共 #{done} 条。"
