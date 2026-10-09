class CreateXPosts < ActiveRecord::Migration[6.1]
  def change
    create_table :x_posts do |t|
      t.string :task_type, null: false, comment: '本系统任务模型类名（如 MoveTask）'
      t.bigint :task_id, null: false, comment: '本系统任务 ID'
      t.string :media_id, comment: 'X 侧 media id'
      t.string :tweet_id, comment: 'X 侧 tweet id（发推成功后写入）'
      t.integer :status, default: 0, null: false, comment: '状态 0处理中 1成功 2失败'
      t.text :error_msg, comment: '失败原因'
      t.timestamps
    end

    add_index :x_posts, [:task_type, :task_id]
    add_index :x_posts, :status
    add_index :x_posts, :media_id
  end
end
