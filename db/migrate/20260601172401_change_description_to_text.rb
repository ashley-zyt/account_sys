class ChangeDescriptionToTextInOperationTasks < ActiveRecord::Migration[7.0]
  def change
    change_column :operation_tasks, :description, :text
  end
end