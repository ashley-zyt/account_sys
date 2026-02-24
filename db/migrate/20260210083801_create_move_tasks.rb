class CreateMoveTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :move_tasks do |t|
      t.string :task_uuid, comment: '任务唯一标识，用于关联日志'

      # 视频与账号信息
      t.string  :video_url,        comment: '源视频地址'
      t.string  :source_account_url, comment: '来源账号主页链接'
      t.bigint  :account_id, comment: '发布账号ID'

      t.string :theme, comment: '内容主题'
      t.text :title, comment: '发布标题'

      # 任务状态
      t.integer :status, default: 0, comment: '任务状态 pending/waiting_publish/executing/success/failed'
      t.text    :error_msg,        comment: '错误信息/失败原因'

      # 时间信息
      t.datetime :start_at,            comment: '任务开始时间'
      t.datetime :actual_publish_time, comment: '实际发布时间'

      # 执行环境
      t.bigint :browser_id, comment: '执行任务的浏览器ID'

      t.timestamps
    end

    add_index :move_tasks, :task_uuid, unique: true
    add_index :move_tasks, :browser_id
    add_index :move_tasks, :status
  end
end
