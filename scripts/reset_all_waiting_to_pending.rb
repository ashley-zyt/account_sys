# -*- coding: utf-8 -*-
# 将所有工作模式资源队列里的 waiting_publish（等待发布）任务，重置为 pending（待分配），
# 供「从头测试发布流程」使用。
#
# 用法：
#   bundle exec rails runner scripts/reset_all_waiting_to_pending.rb           # 预览（只统计，不改数据）
#   bundle exec rails runner scripts/reset_all_waiting_to_pending.rb confirm   # 执行
#
# 处理逻辑（每个资源队列模型）：
#   将 status=waiting_publish 的任务批量更新为 status=pending，并清空
#   account_id / browser_id / start_at / error_msg（回到「未分配」的干净初始态）。
#   成功（success）与执行中（executing）的任务不动，避免误伤。

confirm_mode = ARGV[0] == 'confirm'

models = WorkMode.resource_modes.map(&:task_model_class)

puts "===== waiting_publish 任务重置（#{confirm_mode ? '执行' : '预览'}）====="

rows = []
total = 0
models.each do |model|
  wp = model.statuses['waiting_publish']
  next if wp.nil?

  count = model.where(status: wp).count
  rows << [model, count]
  total += count
  puts format("  %-20s %d 条", model.name, count)
end
puts ""
puts "合计：#{total} 条 waiting_publish"

unless confirm_mode
  puts ""
  puts "这是预览，未做任何修改。确认无误后执行："
  puts "  bundle exec rails runner scripts/reset_all_waiting_to_pending.rb confirm"
  exit
end

puts ""
puts "===== 开始执行 ====="

rows.each do |model, count|
  next if count.zero?

  wp      = model.statuses['waiting_publish']
  pending = model.statuses['pending']
  updated = model.where(status: wp)
                 .update_all(status: pending, account_id: nil, browser_id: nil, start_at: nil, error_msg: nil)
  puts format("  %-20s 已重置 %d 条 → pending", model.name, updated)
end

puts ""
puts "===== 完成 ====="
puts "所有 waiting_publish 任务已重置为 pending，可从头开始调度测试。"
