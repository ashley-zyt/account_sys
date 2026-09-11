# frozen_string_literal: true

# 将花生视频储备（huasheng_keywords）中：
#   theme = 花生视频-抖音号视频号 且 id >= 673
# 的记录重置为「待执行」(status=1)，并清除视频资源队列（huasheng_tasks）中对应的记录。
#
# 处理逻辑：
#   1. 删除这些关键词在 huasheng_tasks 中的全部任务（含各状态）
#   2. 关键词重置为 status=1（待执行），同时清空 task_id / result_data / pushed
#      —— result_data 清空后由流水线重新执行生成；pushed 置 false 以便重新入库资源队列
#
# 用法：
#   bundle exec rails runner scripts/reset_huasheng_dy_sph_keywords.rb            # 预览（只统计，不改数据）
#   bundle exec rails runner scripts/reset_huasheng_dy_sph_keywords.rb confirm    # 执行

require 'benchmark'

THEME = "花生视频-抖音号视频号".freeze
MIN_ID = 673

confirm_mode = ARGV[0] == 'confirm'

keywords = HuashengKeyword.where(theme: THEME).where('id >= ?', MIN_ID).order(:id)
found_ids = keywords.pluck(:id)

puts "===== 花生视频储备重置（#{confirm_mode ? '执行' : '预览'}）====="
puts "条件：theme=#{THEME} 且 id >= #{MIN_ID}"
puts "找到：#{found_ids.size} 条"

if found_ids.empty?
  puts "没有符合条件的记录，退出。"
  exit 0
end

status_names = HuashengKeyword::STATUS_NAMES
total_tasks = 0

puts ""
keywords.each do |kw|
  task_count = HuashengTask.where(huasheng_keyword_id: kw.id).count
  total_tasks += task_count
  puts "  ID=#{kw.id}  key=#{kw.keyword}  状态=#{status_names[kw.status] || kw.status}  pushed=#{kw.pushed}  队列任务 #{task_count} 条"
end

puts ""
puts "合计：关键词 #{found_ids.size} 条，将删除队列任务 #{total_tasks} 条"

unless confirm_mode
  puts ""
  puts "这是预览，未做任何修改。确认无误后执行："
  puts "  bundle exec rails runner scripts/reset_huasheng_dy_sph_keywords.rb confirm"
  exit
end

puts ""
puts "===== 开始执行 ====="
deleted_tasks = 0

time = Benchmark.measure do
  ActiveRecord::Base.transaction do
    deleted_tasks = HuashengTask.where(huasheng_keyword_id: found_ids).delete_all

    keywords.update_all(
      status: 1,          # 待执行
      task_id: nil,
      result_data: nil,
      pushed: false,
      updated_at: Time.current
    )
  end
end

puts "已删除队列任务 #{deleted_tasks} 条"
puts "已重置关键词 #{found_ids.size} 条为「待执行」(status=1)，并清空 task_id / result_data / pushed"
puts "耗时: #{time.real.round(2)} 秒"

puts ""
puts "===== 重置后的 ID 列表（共 #{found_ids.size} 个）====="
puts found_ids.inspect
puts ""
puts "===== 完成 ====="
