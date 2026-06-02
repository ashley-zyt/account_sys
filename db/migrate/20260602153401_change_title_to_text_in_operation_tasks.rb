class ChangeTitleToTextInOperationTasks < ActiveRecord::Migration[6.1]
  def change
    change_column :operation_tasks, :title, :text
  end
end