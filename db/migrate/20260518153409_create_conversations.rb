class CreateConversations < ActiveRecord::Migration[6.1]
  def change
    create_table :conversations do |t|
      t.bigint :kol_id, null: false, comment: "KOL ID"

      t.bigint :kol_platform_account_id, null: false, comment: "KOL平台账号ID"
      t.bigint :social_account_id, null: false, comment: "运营账号ID"

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

    add_index :conversations, :kol_id 
    add_index :conversations, :kol_platform_account_id 
    add_index :conversations, :social_account_id 
    add_index :conversations, :platform 
    add_index :conversations, :status 
    add_index :conversations, :last_message_at
  end
end