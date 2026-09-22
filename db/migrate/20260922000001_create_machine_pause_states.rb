# 运营机器「Undetectable 未启动导致任务暂停」的暂停周期状态。
#
# 背景：机器端因 Undetectable 未启动把任务标为 paused 时刻意不回调 account_sys
# （ls `finalizeAsyncTask`：paused 不回调、不标失败），所以 account_sys 必须自己去查、
# 自己去恢复，并记住「这台机器从什么时候开始暂停、有没有提醒过」。
#
# 每台机器一条记录（machine_ip 唯一）：
#   - paused_since  本轮暂停的起始时刻（首次发现该机器有 paused 任务时写入；恢复正常后清空）
#   - notified_at   本轮是否已发过钉钉提醒（只提醒一次，避免每 5 分钟刷屏）
#   - resumed_at    最近一次自动恢复成功的时刻（供排查「上次是什么时候自己好的」）
class CreateMachinePauseStates < ActiveRecord::Migration[6.1]
  def change
    create_table :machine_pause_states do |t|
      t.string   :machine_ip, null: false, comment: "运营机器 IP（唯一）"
      t.datetime :paused_since, comment: "本轮暂停起始时刻（恢复正常后置空）"
      t.datetime :notified_at, comment: "本轮已发钉钉提醒的时刻（只提醒一次）"
      t.datetime :resumed_at, comment: "最近一次自动恢复成功的时刻"
      t.integer  :paused_count, default: 0, comment: "最近一次看到的暂停任务数"
      t.text     :last_message, comment: "最近一次处理结果摘要（恢复/提醒/重发情况）"

      t.timestamps
    end

    add_index :machine_pause_states, :machine_ip, unique: true
  end
end
