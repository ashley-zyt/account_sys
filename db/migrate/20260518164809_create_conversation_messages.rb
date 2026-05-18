class CreateConversationMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :conversation_messages do |t|
      t.references :conversation,type: :bigint,
                   null: false,
                   foreign_key: true

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

    add_index :conversation_messages, :sender_type
    add_index :conversation_messages, :sent_at
  end
end