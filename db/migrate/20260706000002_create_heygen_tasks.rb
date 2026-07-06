class CreateHeygenTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :heygen_tasks do |t|
      t.string :theme,             comment: '主题'
      t.text   :video_url,         comment: '视频OSSurl'
      t.integer :status,           default: 0, comment: '任务状态 pending/waiting_publish/executing/success/failed'
      t.string :templete_id,       comment: '视频模板ID'
      t.text   :video_text,        comment: '逐字稿'
      t.bigint :account_id,        comment: '账号ID'
      t.bigint :browser_id,        comment: '浏览器ID'
      t.text   :error_msg,         comment: '任务结果'
      t.datetime :start_at,        comment: '任务开始时间'
      t.datetime :actual_publish_time, comment: '实际发布时间'
      t.string :task_uuid,         comment: '任务唯一标识，用于关联日志'
      t.integer :platform,         comment: '平台'
      t.text   :title,             comment: '标题'
      t.text   :description,       comment: '描述'

      t.timestamps
    end

    add_index :heygen_tasks, :task_uuid, unique: true
    add_index :heygen_tasks, :account_id
    add_index :heygen_tasks, :browser_id
    add_index :heygen_tasks, :status
    add_index :heygen_tasks, :platform
    add_index :heygen_tasks, :theme
    add_index :heygen_tasks, :templete_id
  end
end