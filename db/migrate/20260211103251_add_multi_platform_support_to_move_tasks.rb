class AddMultiPlatformSupportToMoveTasks < ActiveRecord::Migration[5.2]
  def change
    # 1. 添加 platform 字段（枚举，与 Account.platform 一致）
    add_column :move_tasks, :platform, :integer, comment: '目标发布平台'

    # 2. 添加 group_id，关联同一视频的多平台任务
    add_column :move_tasks, :group_id, :string, comment: '任务组ID，同一视频的多平台任务共享'

    # 3. 移除原有的 video_url 唯一索引（如果存在）
    remove_index :move_tasks, :video_url if index_exists?(:move_tasks, :video_url)

    # 4. 添加组合唯一索引，保证同一视频在单个平台只有一个任务
    add_index :move_tasks, [:video_url, :platform], unique: true, name: 'idx_move_tasks_video_platform'

    # 5. 为 platform 和 group_id 添加索引（加速查询）
    add_index :move_tasks, :platform
    add_index :move_tasks, :group_id
  end
end