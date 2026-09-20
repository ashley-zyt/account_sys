# 异步浏览器任务登记表：记录 account_sys 下发到机器端的 async 任务的机器端 task_id，
# 用于「页面查看任务执行状态」和「超时兜底主动查询机器端真实状态」。
class CreateBrowserTaskRecords < ActiveRecord::Migration[6.1]
  def change
    create_table :browser_task_records do |t|
      t.string  :machine_task_id, null: false, comment: "机器端返回的 task_id"
      t.string  :ref,             comment: "account_sys 业务透传标识（如 MoveTask:123 / WarmupTask:456）"
      t.string  :task_type,       comment: "机器端任务类型（nurture/fetch/send_message/check_reply/5 个 publish）"
      t.string  :profile_name,    comment: "指纹浏览器名"
      t.string  :machine_ip,      comment: "运营机器 IP/域名"
      t.string  :status,          default: "pending", comment: "本地记录状态：pending/success/failed/unknown"
      t.text    :message,         comment: "机器端回调的 message（动作统计或错误信息）"

      t.timestamps
    end

    add_index :browser_task_records, :machine_task_id, unique: true
    add_index :browser_task_records, :status
    add_index :browser_task_records, :created_at
  end
end
