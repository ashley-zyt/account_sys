class RemovePlatformStringFormOperationTasks < ActiveRecord::Migration[6.1]
  def change
    remove_column :operation_tasks, :platform_string
  end
end