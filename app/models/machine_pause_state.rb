# == Schema Information
#
# Table name: machine_pause_states
#
#  id                                                       :bigint           not null, primary key
#  last_message(最近一次处理结果摘要（恢复/提醒/重发情况）) :text(65535)
#  machine_ip(运营机器 IP（唯一）)                          :string(255)      not null
#  notified_at(本轮已发钉钉提醒的时刻（只提醒一次）)        :datetime
#  paused_count(最近一次看到的暂停任务数)                   :integer          default(0)
#  paused_since(本轮暂停起始时刻（恢复正常后置空）)         :datetime
#  resumed_at(最近一次自动恢复成功的时刻)                   :datetime
#  created_at                                               :datetime         not null
#  updated_at                                               :datetime         not null
#
# Indexes
#
#  index_machine_pause_states_on_machine_ip  (machine_ip) UNIQUE
#
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
