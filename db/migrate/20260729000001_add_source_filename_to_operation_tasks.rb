class AddSourceFilenameToOperationTasks < ActiveRecord::Migration[6.1]
  def change
    add_column :operation_tasks, :source_filename, :string
    add_index :operation_tasks, :source_filename
  end
end
