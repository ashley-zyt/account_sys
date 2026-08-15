class CreateHuashengKeywords < ActiveRecord::Migration[6.1]
  def change
    create_table :huasheng_keywords do |t|
      t.string :theme, null: false, comment: "主题"
      t.string :keyword, null: false, comment: "关键词"
      t.integer :status, default: 0, comment: "任务状态：0未启动 1待执行 2执行中 3执行完成 4任务失败"
      t.string :task_id, comment: "远程任务ID"
      t.text :result_data, comment: "采集结果数据（JSON）"
      t.timestamps
    end

    add_index :huasheng_keywords, :theme
    add_index :huasheng_keywords, :status
    add_index :huasheng_keywords, [:theme, :status]
  end
end
