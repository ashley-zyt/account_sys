class MoveProcessedOssUrlToMoveTask < ActiveRecord::Migration[6.1]
  # 将剪映成片 OSS URL 的存储位置从 move_video.processed_oss_url 迁移到 move_task.oss_url
  # 目的：与 jianying_task / grok_task / heygen_task 等资源队列结构一致，发布时直接读 move_task.oss_url
  #
  # 幂等：用 column_exists? 守卫，兼容两种状态——
  #   a) 原迁移已跑（move_video 有 processed_oss_url、move_task 无 oss_url）：本迁移回填数据后删列加列
  #   b) 原迁移已含最终结构（move_video 无 processed_oss_url、move_task 有 oss_url）：本迁移全部跳过
  def up
    # 1. move_task 加 oss_url（若不存在）
    add_column :move_tasks, :oss_url, :text, comment: '剪映处理后视频 OSS URL（发布用）' unless column_exists?(:move_tasks, :oss_url)

    # 2. 数据回填：已 processed 的 move_video.processed_oss_url 写入关联 move_task.oss_url
    if column_exists?(:move_videos, :processed_oss_url)
      execute <<~SQL
        UPDATE move_tasks
        INNER JOIN move_videos ON move_videos.id = move_tasks.move_video_id
        SET move_tasks.oss_url = move_videos.processed_oss_url
        WHERE move_videos.processed_oss_url IS NOT NULL
          AND move_tasks.oss_url IS NULL
      SQL
      # 3. move_video 移除 processed_oss_url
      remove_column :move_videos, :processed_oss_url, :text
    end
  end

  def down
    add_column :move_videos, :processed_oss_url, :text, comment: '剪映处理后 OSS URL（发布用）' unless column_exists?(:move_videos, :processed_oss_url)

    # 反向回填（可选）：move_task.oss_url → move_video.processed_oss_url
    if column_exists?(:move_tasks, :oss_url)
      execute <<~SQL
        UPDATE move_videos
        INNER JOIN move_tasks ON move_tasks.move_video_id = move_videos.id
        SET move_videos.processed_oss_url = move_tasks.oss_url
        WHERE move_tasks.oss_url IS NOT NULL
          AND move_videos.processed_oss_url IS NULL
      SQL
      remove_column :move_tasks, :oss_url, :text
    end
  end
end
