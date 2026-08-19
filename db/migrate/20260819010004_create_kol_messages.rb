class CreateKolMessages < ActiveRecord::Migration[6.1]
  def change
    create_table :kol_messages do |t|
      t.references :kol, type: :bigint, null: false, foreign_key: true
      t.references :kol_contact, type: :bigint, null: true, foreign_key: true
      t.references :account, type: :bigint, null: true, foreign_key: true
      t.references :message_template, type: :bigint, null: true, foreign_key: true

      t.integer :platform, null: false, comment: "平台/渠道"

      # 方向：outgoing 我方发出 / incoming 对方回复
      t.integer :direction, null: false, default: 0, comment: "消息方向"
      # 来源：auto 自动 / manual 人工
      t.integer :source, null: false, default: 0, comment: "消息来源"

      t.text :content, comment: "消息内容"

      # 第二层：会话执行状态
      # queued / sent_success / sent_failed / replied / ignored
      t.integer :status, null: false, default: 0, comment: "会话执行状态"

      t.text :error_msg, comment: "失败原因"
      t.datetime :occurred_at, comment: "消息发生时间"
      t.datetime :wait_until, comment: "等待回复截止时间"
      t.boolean :is_auto_reply, null: false, default: false, comment: "是否为自动回复（假回复）"

      t.timestamps
    end

    add_index :kol_messages, :kol_id
    add_index :kol_messages, :kol_contact_id
    add_index :kol_messages, :account_id
    add_index :kol_messages, :status
    add_index :kol_messages, :direction
    add_index :kol_messages, :occurred_at
  end
end
