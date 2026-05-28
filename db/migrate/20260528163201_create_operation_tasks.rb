class CreateOperationTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :operation_tasks do |t|
      t.string :theme, comment: '主题'
      t.string :title, comment: '标题'
      t.string :oss_url, comment: 'OSS文件地址'
      t.bigint :account_id, comment: '账号ID'
      t.string :status, default: 'pending', comment: '状态(pending/processing/completed/failed)'
      t.text :error_msg, comment: '错误信息'
      t.datetime :start_at, comment: '开始时间'
      t.datetime :actual_publish_time, comment: '实际发布时间'
      t.string :browser_id, comment: '浏览器ID'
      t.string :platform, comment: '平台'
      t.bigint :group_id, comment: '分组ID'
      t.string :task_uuid, comment: '任务UUID'

      t.timestamps
    end

    add_index :operation_tasks, :account_id
    add_index :operation_tasks, :status
    add_index :operation_tasks, :task_uuid, unique: true
    add_index :operation_tasks, :platform
    add_index :operation_tasks, [:oss_url, :platform], unique: true, name: 'index_operation_tasks_on_oss_url_and_platform'
    add_index :operation_tasks, [:account_id, :oss_url], unique: true, name: 'index_operation_tasks_on_account_id_and_oss_url'
  end
end