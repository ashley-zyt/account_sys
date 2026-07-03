class CreateRedNoteKeywords < ActiveRecord::Migration[6.1]
  def change
    create_table :red_note_keywords do |t|
      t.string :theme, null: false, comment: "主题"
      t.string :keyword, null: false, comment: "关键词"
      t.string :keyword_code, null: false, comment: "关键词唯一编码"
      t.integer :status, default: 0, comment: "任务状态：0未启动 1待执行 2执行中 3执行完成 4任务失败"
      t.string :task_id, comment: "远程任务ID"
      t.text :result_data, comment: "采集结果数据（JSON）"
      t.timestamps
    end

    add_index :red_note_keywords, :keyword_code, unique: true
    add_index :red_note_keywords, :theme
    add_index :red_note_keywords, :status
    add_index :red_note_keywords, [:theme, :status]
  end
end
