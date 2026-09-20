# KOL 触达动作日志表：记录「发私信」「检查回复」每次动作的执行流水，
# 用于后台查看 KOL 触达的操作记录与结果（独立于业务表 KolMessage）。
#
# 写入时机：
#   - 下发 async 任务、机器端返回 accepted 时登记一条 pending；
#   - 机器端回调结果时按 machine_task_id 更新为 success/failed。
class CreateKolActionLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :kol_action_logs do |t|
      t.string  :action_type,     null: false, comment: "动作类型：send_message(发私信) / check_reply(检查回复)"
      t.bigint  :kol_id,          comment: "关联 KOL"
      t.bigint  :kol_contact_id,  comment: "关联联系方式"
      t.bigint  :account_id,      comment: "执行用的内部账号（可空）"
      t.string  :machine_task_id, comment: "机器端返回的 task_id（可空，用于回调时定位）"
      t.string  :status,          default: "pending", comment: "记录状态：pending/success/failed"
      t.text    :message,         comment: "结果/错误信息"

      t.timestamps
    end

    add_index :kol_action_logs, :action_type
    add_index :kol_action_logs, :kol_id
    add_index :kol_action_logs, :kol_contact_id
    add_index :kol_action_logs, :account_id
    add_index :kol_action_logs, :machine_task_id
    add_index :kol_action_logs, :status
    add_index :kol_action_logs, :created_at
  end
end
