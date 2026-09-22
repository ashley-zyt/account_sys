# 任务「发活」时的归属快照表。
#
# 背景（2026-09-22 排查）：
#   资源队列任务的 account_id / browser_id 会在「释放」时被清空（重置回 pending、被超时兜底重置、
#   失败回退、批量回退等），而回调是异步的、常常晚于释放。若在回调落 task_logs 时才去读任务上的
#   归属，就会读到 nil（任务已被释放），或者读到新账号（任务释放后又被重新分配）——
#   表现就是 task_logs 对不上账号和浏览器，甚至张冠李戴。
#
# 解决：在「发活」（分配账号/浏览器）那一刻把归属写进本表；释放时只写 released_at、不删记录。
#   回调落 task_logs 时优先用这份快照。
#
# 关联方式与 task_logs 一致（按 task_uuid），因此一处即可覆盖
#   move / operation / jianying / grok / heygen 全部资源队列模式。
class CreateTaskAssignments < ActiveRecord::Migration[6.1]
  def change
    create_table :task_assignments do |t|
      t.string   :task_uuid,      null: false, comment: '资源队列任务的 task_uuid（与 task_logs 同一关联方式）'
      t.string   :task_type,                  comment: '工作模式 key（move/operation/jianying/grok/heygen），便于排查'
      t.bigint   :account_id,                 comment: '发活时分配的账号（任务释放后仍保留）'
      t.string   :browser_id,                 comment: '发活时分配的浏览器（任务释放后仍保留）'
      t.datetime :assigned_at,                comment: '本次发活时间'
      t.datetime :released_at,                comment: '本次归属被释放的时间（重置/中断/失败回退时写入）'
      t.string   :release_reason,             comment: '释放原因'

      t.timestamps
    end

    add_index :task_assignments, :task_uuid
    add_index :task_assignments, [:task_uuid, :released_at], name: 'index_task_assignments_on_uuid_and_released_at'
    add_index :task_assignments, :account_id
    add_index :task_assignments, :browser_id
    add_index :task_assignments, :assigned_at
  end
end
