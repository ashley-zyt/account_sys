# -*- coding: utf-8 -*-
# 回填 task_logs.publish_channel：修复「字符串转 0」导致的历史数据错误。
#
# 背景：TaskLog 之前缺 enum publish_channel，写日志时传字符串 'postforme'/'x_api'/'ag_center'
#       被 ActiveRecord 按整数列转换（.to_i）成 0，导致所有发布日志 publish_channel=0，
#       后台按渠道筛选 postforme(1)/x_api(2) 匹配不到。
# 修复：给 TaskLog 补上 enum publish_channel 后，本脚本按 task_uuid 关联
#       postforme_posts / x_posts，把对应日志的 publish_channel 修正为 1 / 2。
#
# 用法：
#   bundle exec rails runner scripts/backfill_task_log_publish_channel.rb           # 预览（只统计）
#   bundle exec rails runner scripts/backfill_task_log_publish_channel.rb confirm   # 执行回填

confirm = ARGV.include?('confirm')

puts "===== 回填 task_logs.publish_channel（#{confirm ? '执行' : '预览'}）====="
puts "当前分布：#{TaskLog.group(:publish_channel).count.sort_by { |k, _| k.to_s }.to_h.inspect}"
puts ""

# 收集 postforme / x_api 各自关联的 task_uuid
postforme_uuids = {}
PostformePost.find_each do |pp|
  task = pp.task
  postforme_uuids[task.task_uuid] = true if task&.task_uuid
end

x_uuids = {}
XPost.find_each do |xp|
  task = xp.task
  x_uuids[task.task_uuid] = true if task&.task_uuid
end

postforme_targets = TaskLog.where(task_uuid: postforme_uuids.keys, publish_channel: 0)
x_targets = TaskLog.where(task_uuid: x_uuids.keys, publish_channel: 0)

puts "postforme 关联 task_uuid：#{postforme_uuids.size} 个，待修正日志 #{postforme_targets.count} 条"
puts "x_api     关联 task_uuid：#{x_uuids.size} 个，待修正日志 #{x_targets.count} 条"
puts ""

if confirm
  n1 = postforme_targets.update_all(publish_channel: 1)
  n2 = x_targets.update_all(publish_channel: 2)
  puts "已回填：postforme=#{n1}，x_api=#{n2}"
  puts "回填后分布：#{TaskLog.group(:publish_channel).count.sort_by { |k, _| k.to_s }.to_h.inspect}"
else
  puts "预览模式，未做任何改动。确认后执行："
  puts "  bundle exec rails runner scripts/backfill_task_log_publish_channel.rb confirm"
end
