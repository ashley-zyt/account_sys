class AddSourceTypeToMoveTasks < ActiveRecord::Migration[6.1]
  def change
    add_column :move_tasks, :source_type, :integer, comment:"资源数据类型"
    add_index :move_tasks, :source_type
  end
end