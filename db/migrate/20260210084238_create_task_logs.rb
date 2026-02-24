class CreateTaskLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :task_logs do |t|
      t.string :task_uuid, comment: '关联的任务UUID'

      # 请求与响应数据
      t.text :request_data,  comment: '请求参数/发送内容'
      t.text :response_data, comment: '接口返回数据'

      t.integer :status, default: 0, comment: '执行结果 success/failed'
      t.text    :error_msg, comment: '执行错误信息'

      t.datetime :run_at, comment: '执行时间'

      t.timestamps
    end

    add_index :task_logs, :task_uuid
    add_index :task_logs, :status
  end
end
