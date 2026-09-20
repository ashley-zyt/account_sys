# == Schema Information
#
# Table name: kol_action_logs
#
#  id                                             :bigint           not null, primary key
#  action_type(动作类型：send_message/check_reply) :string(255)      not null
#  account_id(执行用的内部账号)                   :bigint
#  kol_contact_id(关联联系方式)                   :bigint
#  kol_id(关联 KOL)                               :bigint
#  machine_task_id(机器端返回的 task_id)          :string(255)
#  status(记录状态：pending/success/failed)       :string(255)      default("pending")
#  message(结果/错误信息)                         :text(65535)
#  created_at                                     :datetime         not null
#  updated_at                                     :datetime         not null
#
# KOL 触达动作日志 —— 记录「发私信」「检查回复」每次动作的执行流水。
#
# 与 KolMessage 的区别：KolMessage 记录的是「消息」本身（内容、方向、会话状态），
# 本表记录的是「动作」流水（每次调用机器端发消息/查回复，无论最终有无消息产生）。
class KolActionLog < ApplicationRecord
  belongs_to :kol, optional: true
  belongs_to :kol_contact, optional: true
  belongs_to :account, optional: true

  ACTION_SEND = 'send_message'.freeze
  ACTION_CHECK = 'check_reply'.freeze

  ACTION_TYPE_LABELS = {
    ACTION_SEND  => '发私信',
    ACTION_CHECK => '检查回复'
  }.freeze

  STATUS_PENDING = 'pending'.freeze
  STATUS_SUCCESS = 'success'.freeze
  STATUS_FAILED  = 'failed'.freeze

  STATUS_LABELS = {
    STATUS_PENDING => '执行中',
    STATUS_SUCCESS => '成功',
    STATUS_FAILED  => '失败'
  }.freeze

  validates :action_type, presence: true

  def action_type_label
    ACTION_TYPE_LABELS[action_type] || action_type.to_s
  end

  def status_label
    STATUS_LABELS[status] || status.to_s
  end

  # 下发 async 任务、机器端返回 accepted 时登记一条 pending
  def self.track!(action_type:, kol_id: nil, kol_contact_id: nil, account_id: nil, machine_task_id: nil, message: nil)
    create!(
      action_type: action_type,
      kol_id: kol_id,
      kol_contact_id: kol_contact_id,
      account_id: account_id,
      machine_task_id: machine_task_id,
      status: STATUS_PENDING,
      message: message
    )
  end

  # 机器端回调时按 machine_task_id 更新状态（找不到或没有 task_id 则忽略）
  def self.mark_result!(machine_task_id, status, message = nil)
    return if machine_task_id.blank?
    rec = where(machine_task_id: machine_task_id).order(created_at: :desc).first
    return unless rec
    rec.update!(
      status: (status == 'success' ? STATUS_SUCCESS : STATUS_FAILED),
      message: message.presence || rec.message
    )
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id action_type kol_id kol_contact_id account_id machine_task_id status message created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol kol_contact account]
  end
end
