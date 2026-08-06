class AddDescriptionToMoveTasks < ActiveRecord::Migration[6.1]
  def change
    add_column :move_tasks, :description, :string, comment: "视频描述"
  end
end
