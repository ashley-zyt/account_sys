class CreateConversations < ActiveRecord::Migration[7.2]
  def change
    create_table :conversations do |t|
      t.references :kol, null: false, foreign_key: true

      t.references :kol_platform_account,
                   null: false,
                   foreign_key: true

      t.references :social_account,
                   null: false,
                   foreign_key: true

      t.integer :platform,
                null: false,
                comment: "平台"

      t.integer :status,
                null: false,
                default: 0,
                comment: "会话状态"

      t.datetime :last_message_at,
                 comment: "最后消息时间"

      t.datetime :closed_at,
                 comment: "关闭时间"

      t.text :latest_message,
             comment: "最新消息摘要"

      t.timestamps
    end

    add_index :conversations, :platform
    add_index :conversations, :status
    add_index :conversations, :last_message_at
  end
end