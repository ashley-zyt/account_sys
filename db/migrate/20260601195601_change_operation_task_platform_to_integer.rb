class ChangeOperationTaskPlatformToInteger < ActiveRecord::Migration[7.0]
  def up
    # 先备份数据
    rename_column :operation_tasks, :platform, :platform_string
    
    # 添加新的 integer 字段
    add_column :operation_tasks, :platform, :integer
    
    # 迁移数据
    OperationTask.reset_column_information
    OperationTask.find_each do |task|
      platform_map = {
        '1' => 1,
        '2' => 2,
        '3' => 3,
        '4' => 4,
        '5' => 5
      }
      task.update_column(:platform, platform_map[task.platform_string] || 0)
    end
    
    # 删除旧字段
    remove_column :operation_tasks, :platform_string
  end

  def down
    # 添加回 string 字段
    add_column :operation_tasks, :platform_string, :string
    
    # 迁移数据
    OperationTask.reset_column_information
    platform_map = {
      1 => 'facebook',
      2 => 'twitter',
      3 => 'tiktok',
      4 => 'youtube',
      5 => 'instagram'
    }
    OperationTask.find_each do |task|
      task.update_column(:platform_string, platform_map[task.platform] || '')
    end
    
    # 删除 integer 字段
    remove_column :operation_tasks, :platform
    
    # 恢复原名字段
    rename_column :operation_tasks, :platform_string, :platform
  end
end