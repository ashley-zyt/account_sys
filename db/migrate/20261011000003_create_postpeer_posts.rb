class CreatePostpeerPosts < ActiveRecord::Migration[6.1]
  def change
    create_table :postpeer_posts do |t|
      t.string :post_id, comment: "postpeer 返回的 post ID"
      t.string :peer_account_id, comment: "postpeer 集成 ID（冗余，便于排查）"
      t.string :platform_url, comment: "发布成功后平台上的链接"
      t.integer :status, null: false, default: 0, comment: "状态 0处理中 1成功 2失败"
      t.string :task_type, null: false, comment: "本系统任务模型类名（如 MoveTask）"
      t.bigint :task_id, null: false, comment: "本系统任务 ID"
      t.text :error_msg, comment: "失败原因"
      t.timestamps
    end

    add_index :postpeer_posts, :post_id, unique: true
    add_index :postpeer_posts, :status
    add_index :postpeer_posts, [:task_type, :task_id]
  end
end
