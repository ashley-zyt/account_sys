class ChangeOssUrlToTextInOperationTasks < ActiveRecord::Migration[6.1]
  def up
    # 先删除涉及 oss_url 的索引
    remove_index :operation_tasks, name: 'index_operation_tasks_on_account_id_and_oss_url' rescue nil
    remove_index :operation_tasks, name: 'index_operation_tasks_on_oss_url_and_platform' rescue nil
    
    # 将 oss_url 改为 text 类型
    change_column :operation_tasks, :oss_url, :text
    
    # 重新创建索引（使用前缀索引）
    add_index :operation_tasks, [:account_id, :oss_url], name: 'index_operation_tasks_on_account_id_and_oss_url', unique: true, length: { oss_url: 255 }
    add_index :operation_tasks, [:oss_url, :platform], name: 'index_operation_tasks_on_oss_url_and_platform', unique: true, length: { oss_url: 255 }
  end

  def down
    # 先删除索引
    remove_index :operation_tasks, name: 'index_operation_tasks_on_account_id_and_oss_url' rescue nil
    remove_index :operation_tasks, name: 'index_operation_tasks_on_oss_url_and_platform' rescue nil
    
    # 改回 string 类型
    change_column :operation_tasks, :oss_url, :string
    
    # 重建索引
    add_index :operation_tasks, [:account_id, :oss_url], name: 'index_operation_tasks_on_account_id_and_oss_url', unique: true
    add_index :operation_tasks, [:oss_url, :platform], name: 'index_operation_tasks_on_oss_url_and_platform', unique: true
  end
end