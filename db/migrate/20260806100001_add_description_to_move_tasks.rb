class AddDescriptionToMoveTasks < ActiveRecord::Migration[7.2]
  def change
    add_column :move_tasks, :description, :string, comment: "视频描述"
  end
end
