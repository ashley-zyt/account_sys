class AddDescriptionToOperationTasks < ActiveRecord::Migration[6.1]
  def change
    add_column :operation_tasks, :description, :string
  end
end