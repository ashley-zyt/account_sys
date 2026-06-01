class ChangeDescriptionToTextInOperationTasks < ActiveRecord::Migration[6.1]
  def change
    change_column :operation_tasks, :description, :text
  end
end