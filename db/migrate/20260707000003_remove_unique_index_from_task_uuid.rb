class RemoveUniqueIndexFromTaskUuid < ActiveRecord::Migration[6.1]
  def change
    remove_index :heygen_tasks, :task_uuid
  end
end