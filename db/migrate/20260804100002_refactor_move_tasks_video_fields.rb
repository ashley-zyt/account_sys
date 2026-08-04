class RefactorMoveTasksVideoFields < ActiveRecord::Migration[6.1]
  def up
    # 1. 新增 move_video_id 关联字段（不加外键约束，与现有 account_id/browser_id 风格一致）
    add_reference :move_tasks, :move_video, index: false, foreign_key: false

    # 2. 移除旧的 (video_url, platform) 唯一索引
    remove_index :move_tasks, name: 'idx_move_tasks_video_platform'

    # 3. 新唯一索引：(move_video_id, platform)，保证同一视频在同一平台不重复建任务
    add_index :move_tasks, [:move_video_id, :platform], unique: true, name: 'idx_move_tasks_move_video_platform'

    # 4. 新增 oss_url：存储剪映处理后的成片 OSS URL（发布用，与 jianying_task 等资源队列一致）
    add_column :move_tasks, :oss_url, :text, comment: '剪映处理后视频 OSS URL（发布用）'

    # 5. 移除源视频字段（已通过 backup_unpublished_video_urls 备份未发布视频）
    remove_column :move_tasks, :video_url, :string
    remove_column :move_tasks, :source_account_url, :string
  end

  def down
    add_column :move_tasks, :video_url, :string, comment: '源视频地址'
    add_column :move_tasks, :source_account_url, :string, comment: '来源账号主页链接'
    remove_column :move_tasks, :oss_url
    remove_index :move_tasks, name: 'idx_move_tasks_move_video_platform'
    add_index :move_tasks, [:video_url, :platform], unique: true, name: 'idx_move_tasks_video_platform'
    remove_reference :move_tasks, :move_video, index: false, foreign_key: false
  end
end
