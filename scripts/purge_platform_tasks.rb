# -*- coding: utf-8 -*-
# 按平台清除发布任务：把指定平台（如 tiktok）在所有资源队列里的发布任务，
# 以及机器端登记记录（browser_task_records）一并【物理删除】。
#
# 用法：
#   bundle exec rails runner scripts/purge_platform_tasks.rb tiktok            # 预览（只统计，不删）
#   bundle exec rails runner scripts/purge_platform_tasks.rb tiktok confirm    # 执行（物理删除，不可恢复）
#
# 参数：
#   <platform>  目标平台：facebook / twitter / tiktok / youtube / instagram（必填）
#   confirm     加上才真正删除；不加只预览统计
#
# 覆盖范围：
#   1. WorkMode.publishable_modes 里每个资源队列（MoveTask/JianyingTask/OperationTask/
#      GrokTask/HeygenTask/HuashengTask/NotebooklmTask）中 platform=该平台的记录，
#      【全部状态，含 success / failed】—— 物理删除，历史不可查；
#   2. browser_task_records 里 task_type="{platform}_publish" 的登记记录。
#
# 提醒：
#   - delete_all 跳过回调、不做备份，删了不可恢复，请务必先跑一次预览看数量。
#   - 删除任务不会自动复活：发布任务只在剪映完成回调（mark_processed!）时创建，
#     不是定时扫描；但源视频的 platforms 字段仍保留该平台，将来想补发需手动重建任务。

platform = ARGV[0].to_s.strip
confirm  = ARGV[1] == 'confirm'

if platform.empty?
  puts "用法："
  puts "  bundle exec rails runner scripts/purge_platform_tasks.rb <platform> [confirm]"
  puts "  platform: facebook / twitter / tiktok / youtube / instagram"
  puts "  confirm:  加 confirm 才真正删除，否则只预览"
  exit 1
end

task_type = "#{platform}_publish"

models = WorkMode.publishable_modes
                 .map(&:task_model_class)
                 .select { |m| m.respond_to?(:platforms) }

puts "===== 清除 #{platform} 发布任务（#{confirm ? '执行' : '预览'}）====="
puts ""

rows = []
total = 0
models.each do |model|
  count = model.where(platform: platform).count
  rows << [model, count]
  total += count
  puts format("  %-22s %d 条", model.name, count)
end

record_count = BrowserTaskRecord.where(task_type: task_type).count
puts format("  %-22s %d 条", "browser_task_records", record_count)
puts ""
puts "合计：#{total + record_count} 条（发布任务 #{total} + 登记 #{record_count}）"

unless confirm
  puts ""
  puts "这是预览，未做任何修改。确认无误后执行："
  puts "  bundle exec rails runner scripts/purge_platform_tasks.rb #{platform} confirm"
  exit
end

puts ""
puts "===== 开始执行（物理删除）====="

deleted = 0
rows.each do |model, count|
  next if count.zero?
  n = model.where(platform: platform).delete_all
  deleted += n
  puts format("  %-22s 已删 %d 条", model.name, n)
end

if record_count > 0
  n = BrowserTaskRecord.where(task_type: task_type).delete_all
  deleted += n
  puts format("  %-22s 已删 %d 条", "browser_task_records", n)
end

puts ""
puts "===== 完成 ====="
puts "已物理删除 #{platform} 发布任务及登记共 #{deleted} 条。"
