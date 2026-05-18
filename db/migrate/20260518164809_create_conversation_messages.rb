class CreateConversationMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :conversation_messages do |t|

      t.bigint :conversation_id,
               null: false,
               comment: "会话ID"

      t.integer :sender_type,
                null: false,
                comment: "发送方类型"

      t.text :content,
             null: false,
             comment: "消息内容"

      t.datetime :sent_at,
                 comment: "发送时间"

      t.timestamps
    end

    add_index :conversation_messages, :conversation_id
    add_index :conversation_messages, :sender_type
    add_index :conversation_messages, :sent_at

    add_foreign_key :conversation_messages, :conversations
  end
end