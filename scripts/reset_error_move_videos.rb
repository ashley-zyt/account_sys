# 将指定 ID 的搬运视频：清除其队列任务 + 重置为「待剪映」状态
#
# 用法：
#   bundle exec rails runner scripts/reset_error_move_videos.rb            # 预览（只统计，不改数据）
#   bundle exec rails runner scripts/reset_error_move_videos.rb confirm    # 执行
#
# 处理逻辑（每个视频）：
#   1. 删除对应的 move_tasks（队列数据，含成片 oss_url）及其关联的 task_logs
#      —— 注：剪映成片 URL 已迁移到 move_task.oss_url（move_videos 已无 processed_oss_url 字段），
#         所以删队列任务 = 清掉错误成片
#   2. 将 move_video 状态重置为 pending_process（待剪映），清空：
#      - processed_at / process_started_at（剪映时间戳）
#      - error_msg（错误信息）
#   3. 保留 raw_oss_url（原始视频，作为重新剪映的输入）

VIDEO_IDS = [728, 731, 736, 738, 739, 2373, 2376, 2378, 2392, 2394, 2396, 2398, 2400, 2403, 2406, 2407].freeze

confirm_mode = ARGV[0] == 'confirm'

videos = MoveVideo.where(id: VIDEO_IDS).order(:id)
found_ids = videos.pluck(:id)
missing_ids = VIDEO_IDS - found_ids

puts "===== 搬运视频重置（#{confirm_mode ? '执行' : '预览'}）====="
puts "目标视频 ID：#{VIDEO_IDS.size} 个"
puts "找到：#{found_ids.size} 个" + (missing_ids.empty? ? '' : "，缺失：#{missing_ids.inspect}")
puts ""

total_tasks = 0
total_logs = 0

videos.each do |v|
  tasks = MoveTask.where(move_video_id: v.id)
  task_count = tasks.count
  uuids = tasks.pluck(:task_uuid)
  oss_count = tasks.where.not(oss_url: [nil, '']).count
  log_count = TaskLog.where(task_uuid: uuids).count
  total_tasks += task_count
  total_logs += log_count

  puts "  视频 ##{v.id} [主题=#{v.theme}]"
  puts "    当前状态：#{v.human_status}  |  队列任务 #{task_count} 条（其中含成片 oss_url #{oss_count} 条）  |  关联日志 #{log_count} 条"
  puts "    raw_oss_url（原始，保留）：#{v.raw_oss_url.present? ? '有' : '无'}"
end

puts ""
puts "合计：队列任务 #{total_tasks} 条，关联日志 #{total_logs} 条"

unless confirm_mode
  puts ""
  puts "这是预览，未做任何修改。确认无误后执行："
  puts "  bundle exec rails runner scripts/reset_error_move_videos.rb confirm"
  exit
end

puts ""
puts "===== 开始执行 ====="
ActiveRecord::Base.transaction do
  videos.each do |v|
    tasks = MoveTask.where(move_video_id: v.id)
    uuids = tasks.pluck(:task_uuid)

    deleted_tasks = tasks.delete_all
    deleted_logs = TaskLog.where(task_uuid: uuids).delete_all

    v.update_columns(
      status: MoveVideo.statuses[:pending_process],
      processed_at: nil,
      process_started_at: nil,
      error_msg: nil,
      updated_at: Time.current
    )

    puts "  视频 ##{v.id}: 删除队列任务 #{deleted_tasks} 条、日志 #{deleted_logs} 条，状态已重置为「待剪映」"
  end
end

puts ""
puts "===== 完成 ====="
puts "已处理 #{found_ids.size} 个视频。它们会重新进入剪映领取队列（claim_for_processing!）。"
