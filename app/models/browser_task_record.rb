# 异步浏览器任务登记表 —— 记录 account_sys 下发到机器端的 async 任务的机器端 task_id。
#
# 用途：
#   1. 后台页面展示「哪些异步任务下发中 / 成功 / 失败」；
#   2. 超时兜底：下发后长时间无回调时，用 machine_task_id 主动查机器端真实状态。
class BrowserTaskRecord < ApplicationRecord
  # 本地记录状态
  STATUS_PENDING = 'pending'.freeze
  STATUS_SUCCESS = 'success'.freeze
  STATUS_FAILED  = 'failed'.freeze
  STATUS_UNKNOWN = 'unknown'.freeze

  validates :machine_task_id, presence: true, uniqueness: true

  scope :pending, -> { where(status: STATUS_PENDING) }

  # 下发 async 任务、机器端返回 accepted 时登记
  def self.track!(machine_task_id:, ref:, task_type:, profile_name:, machine_ip:)
    return if machine_task_id.blank?
    create!(
      machine_task_id: machine_task_id,
      ref: ref,
      task_type: task_type,
      profile_name: profile_name,
      machine_ip: machine_ip,
      status: STATUS_PENDING
    )
  end

  # 机器端回调时更新状态
  def self.mark_result!(machine_task_id, status, message = nil)
    rec = find_by(machine_task_id: machine_task_id)
    return unless rec
    rec.update!(status: (status == 'success' ? STATUS_SUCCESS : STATUS_FAILED), message: message)
  end
end
