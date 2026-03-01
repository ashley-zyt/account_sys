class RemoveSourceTypeFromMoveTasks < ActiveRecord::Migration[6.1]
  def change
    remove_column :move_tasks, :source_type
  end
end