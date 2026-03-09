class CreateJianyingTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :jianying_tasks do |t|
      t.string :task_uuid, comment: '任务唯一标识，用于关联日志'

      # 视频与账号信息
      t.text    :oss_url,          comment: '剪映生成的视频OSS地址'
      t.bigint  :account_id,       comment: '发布账号ID'

      t.string :theme,             comment: '内容主题'
      t.text   :title,             comment: '发布标题'

      # 任务状态
      t.integer :status, default: 0, comment: '任务状态 pending/waiting_publish/executing/success/failed'
      t.text    :error_msg,        comment: '错误信息/失败原因'

      # 时间信息
      t.datetime :start_at,            comment: '任务开始时间'
      t.datetime :actual_publish_time, comment: '实际发布时间'

      # 执行环境
      t.bigint :browser_id, comment: '执行任务的浏览器ID'
      t.integer :platform,  comment: '目标发布平台'
      t.string :group_id,   comment: '任务组ID'

      t.timestamps
    end

    add_index :jianying_tasks, :task_uuid, unique: true
    add_index :jianying_tasks, :browser_id
    add_index :jianying_tasks, :account_id
    add_index :jianying_tasks, :status
    add_index :jianying_tasks, :platform
    add_index :jianying_tasks, :group_id
    add_index :jianying_tasks, :theme
  end
end
