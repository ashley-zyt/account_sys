class AddImmediateToExternalPublishTasks < ActiveRecord::Migration[6.1]
  def change
    add_column :external_publish_tasks, :immediate, :boolean, null: false, default: false
  end
end
