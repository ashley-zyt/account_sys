namespace :move_videos do
  # 从 backup_unpublished_video_urls 产生的 JSON 导入历史未发布视频到 move_videos
  # 按 source_video_url 去重（内存去重 + DB 唯一索引双重保障），已存在的跳过
  # 逻辑见 MoveVideo.import_from_backup!
  #
  # 用法：
  #   rails move_videos:import_from_backup
  #   rails move_videos:import_from_backup BACKUP_PATH=/path/to/file.json
  desc "从备份 JSON 导入历史未发布视频到 move_videos（按 source_video_url 去重）"
  task import_from_backup: :environment do
    path = ENV["BACKUP_PATH"].presence || Rails.root.join("tmp", "unpublished_video_urls.json")
    result = MoveVideo.import_from_backup!(path: path)
    puts "导入完成：共 #{result[:total_records]} 条，去重后 #{result[:unique_records]} 条"
    puts "新建 #{result[:created]} 条，已存在跳过 #{result[:skipped]} 条，失败 #{result[:failed]} 条"
    puts "文件：#{result[:path]}"
  rescue => e
    abort e.message
  end
end
