class CreateMoveVideos < ActiveRecord::Migration[6.1]
  def change
    create_table :move_videos, charset: 'utf8mb4', collation: 'utf8mb4_0900_ai_ci', comment: '搬运视频资源维度表' do |t|
      t.string :source_video_url, null: false, comment: '源视频链接（核心幂等）'
      t.string :source_account_url, comment: '来源账号主页链接'
      t.string :theme, comment: '内容主题'
      t.string :group_id, null: false, comment: '视频组UUID，多平台 move_task 共享'
      t.string :platforms, comment: '目标平台列表，逗号分隔，如 youtube,facebook,twitter,tiktok'
      t.integer :status, default: 0, null: false, comment: '状态 pending_download/downloading/pending_process/processing/processed/failed'

      # OSS 链接（直接存 URL，不存 key、不签名）
      t.text :raw_oss_url, comment: '下载后原始视频 OSS URL'
      t.text :processed_oss_url, comment: '剪映处理后 OSS URL（发布用）'

      t.text :error_msg, comment: '错误信息/失败原因'

      # 阶段时间戳（领取/完成，超时检测预留）
      t.datetime :download_started_at, comment: '下载领取时间'
      t.datetime :downloaded_at, comment: '下载完成时间'
      t.datetime :process_started_at, comment: '剪映领取时间'
      t.datetime :processed_at, comment: '剪映完成时间'

      t.timestamps
    end

    add_index :move_videos, :source_video_url, unique: true, name: 'idx_move_videos_source_video_url'
    add_index :move_videos, :status, name: 'index_move_videos_on_status'
    add_index :move_videos, [:status, :created_at], name: 'idx_move_videos_status_created'
    add_index :move_videos, :group_id, name: 'index_move_videos_on_group_id'
  end
end
