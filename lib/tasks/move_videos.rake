namespace :move_videos do
  # 从 backup_unpublished_video_urls 产生的 JSON 导入历史未发布视频到 move_videos
  # 这些视频将作为 pending_download 进入新的 下载 → 剪映 流程
  #
  # 执行顺序：先 rails db:migrate（建 move_videos 表），再跑本任务
  # 用法：
  #   rails move_videos:import_from_backup
  #   rails move_videos:import_from_backup BACKUP_PATH=/path/to/file.json
  desc "从备份 JSON 导入历史未发布视频到 move_videos（pending_download）"
  task import_from_backup: :environment do
    path = ENV["BACKUP_PATH"].presence || Rails.root.join("tmp", "unpublished_video_urls.json")
    unless File.exist?(path)
      abort "备份文件不存在：#{path}（请先在删除 video_url 字段前运行 MoveTask.backup_unpublished_video_urls 生成）"
    end

    data = JSON.parse(File.read(path))
    records = Array(data["records"])
    created = 0
    skipped = 0
    failed = 0

    records.each do |record|
      video_url = record["video_url"].to_s.strip
      if video_url.blank?
        failed += 1
        next
      end

      platforms = Array(record["platforms"]).map(&:to_s).reject(&:blank?).join(",")
      platforms = MoveVideo::DEFAULT_PLATFORMS.join(",") if platforms.blank?

      existed = MoveVideo.exists?(source_video_url: video_url)
      MoveVideo.find_or_create_by!(source_video_url: video_url) do |v|
        v.source_account_url = record["source_account_url"]
        v.theme = record["theme"]
        v.group_id = record["group_id"].presence || SecureRandom.uuid
        v.platforms = platforms
        v.status = :pending_download
      end
      existed ? skipped += 1 : created += 1
    rescue ActiveRecord::RecordInvalid => e
      failed += 1
      warn "导入失败 video_url=#{video_url}：#{e.message}"
    end

    puts "导入完成：新建 #{created} 条，已存在跳过 #{skipped} 条，失败 #{failed} 条"
  end
end
