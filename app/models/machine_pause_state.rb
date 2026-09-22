# == Schema Information
#
# Table name: machine_pause_states
#
#  id             :bigint           not null, primary key
#  machine_ip(运营机器 IP（唯一）)  :string(255)      not null
#  paused_since(本轮暂停起始时刻（恢复正常后置空）) :datetime
#  notified_at(本轮已发钉钉提醒的时刻（只提醒一次）) :datetime
#  resumed_at(最近一次自动恢复成功的时刻) :datetime
#  paused_count(最近一次看到的暂停任务数) :integer          default(0)
#  last_message(最近一次处理结果摘要) :text(65535)
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_machine_pause_states_on_machine_ip  (machine_ip) UNIQUE
#
# 运营机器「Undetectable 未启动导致任务暂停」的暂停周期状态（每台机器一条）。
#
# 为什么需要它：
#   机器端把因 Undetectable 未启动而无法执行的任务标为 paused 后**不回调 account_sys**，
#   且熔断冷却只有 30 秒、paused 任务不会自己重跑，必须由 account_sys 主动查 + 主动恢复。
#   本表只负责记住「这台机器从什么时候开始暂停、本轮有没有提醒过」，
#   真正的轮询与恢复逻辑在 lib/machine_pause_monitor.rb。
#
# 生命周期：
#   首次发现该机器有 paused 任务 → 写入 paused_since、paused_count
#   自动恢复成功（或已无 paused 任务） → 清空 paused_since / notified_at，paused_count 归零
#   超过阈值仍未恢复 → 发一次钉钉并写 notified_at（本轮不再重复提醒）
class MachinePauseState < ApplicationRecord
  validates :machine_ip, presence: true, uniqueness: true

  scope :paused, -> { where.not(paused_since: nil) }

  # 标记本轮已提醒（只提醒一次，避免每 5 分钟刷屏）
  def notified?
    notified_at.present?
  end

  def paused_seconds
    paused_since ? (Time.current - paused_since).to_i : 0
  end

  # 结束本轮暂停周期：清计时与提醒标记，保留 resumed_at 便于排查「上次是什么时候自己好的」
  def finish_cycle!(message: nil, resumed: false)
    attrs = { paused_since: nil, notified_at: nil, paused_count: 0 }
    attrs[:resumed_at]    = Time.current if resumed
    attrs[:last_message]  = message if message.present?
    update!(attrs)
  end
end
