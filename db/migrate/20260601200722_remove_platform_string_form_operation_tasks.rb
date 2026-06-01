class RemovePlatformStringFormOperationTasks < ActiveRecord::Migration[6.1]
  def change
    remove_index :operation_tasks, column: [:oss_url, :platform_string]
    remove_column :operation_tasks, :platform_string
    add_index :operation_tasks, [:oss_url, :platform], unique: true, name: 'index_operation_tasks_on_oss_url_and_platform'
  end
end