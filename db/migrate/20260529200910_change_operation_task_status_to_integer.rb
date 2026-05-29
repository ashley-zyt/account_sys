class ChangeOperationTaskStatusToInteger < ActiveRecord::Migration[7.0]
  def up
    # 先删除索引
    remove_index :operation_tasks, :status if index_exists?(:operation_tasks, :status)

    # 创建临时列存储新的整数状态
    add_column :operation_tasks, :status_int, :integer, default: 0

    # 迁移数据：字符串 -> 整数
    OperationTask.reset_column_information
    OperationTask.find_each do |task|
      new_status = case task.read_attribute(:status)
                   when 'pending' then 0
                   when 'processing' then 2
                   when 'completed' then 3
                   when 'failed' then 4
                   else 0
                   end
      task.update_column(:status_int, new_status)
    end

    # 删除旧的字符串列
    remove_column :operation_tasks, :status

    # 重命名新列
    rename_column :operation_tasks, :status_int, :status

    # 重新添加索引
    add_index :operation_tasks, :status
  end

  def down
    remove_index :operation_tasks, :status if index_exists?(:operation_tasks, :status)

    add_column :operation_tasks, :status_str, :string, default: 'pending'

    OperationTask.reset_column_information
    OperationTask.find_each do |task|
      new_status = case task.read_attribute(:status)
                   when 0 then 'pending'
                   when 1 then 'waiting_publish'
                   when 2 then 'executing'
                   when 3 then 'success'
                   when 4 then 'failed'
                   else 'pending'
                   end
      task.update_column(:status_str, new_status)
    end

    remove_column :operation_tasks, :status

    rename_column :operation_tasks, :status_str, :status

    add_index :operation_tasks, :status
  end
end