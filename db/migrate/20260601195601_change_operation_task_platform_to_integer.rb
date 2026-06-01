class ChangeOperationTaskPlatformToInteger < ActiveRecord::Migration[6.1]
  def up
    # 先删除唯一索引
    remove_index :operation_tasks, name: 'index_operation_tasks_on_oss_url_and_platform' rescue nil
    
    # 备份数据
    rename_column :operation_tasks, :platform, :platform_string
    
    # 添加新的 integer 字段
    add_column :operation_tasks, :platform, :integer
    
    # 迁移数据
    OperationTask.reset_column_information
    platform_map = {
      'facebook' => 1,
      'twitter' => 2,
      'tiktok' => 3,
      'youtube' => 4,
      'instagram' => 5
    }
    OperationTask.find_each do |task|
      task.update_column(:platform, platform_map[task.platform_string] || 0)
    end
    
    # 删除旧字段
    remove_column :operation_tasks, :platform_string
    
    # 重建唯一索引
    add_index :operation_tasks, [:oss_url, :platform], unique: true
  end

  def down
    # 先删除唯一索引
    remove_index :operation_tasks, name: 'index_operation_tasks_on_oss_url_and_platform' rescue nil
    
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
    
    # 重建唯一索引
    add_index :operation_tasks, [:oss_url, :platform], unique: true
  end
end