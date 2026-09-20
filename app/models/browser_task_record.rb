# == Schema Information
#
# Table name: browser_task_records
#
#  id                                                                               :bigint           not null, primary key
#  machine_ip(运营机器 IP/域名)                                                     :string(255)
#  message(机器端回调的 message（动作统计或错误信息）)                              :text(65535)
#  profile_name(指纹浏览器名)                                                       :string(255)
#  ref(account_sys 业务透传标识（如 MoveTask:123 / WarmupTask:456）)                :string(255)
#  status(本地记录状态：pending/success/failed/unknown)                             :string(255)      default("pending")
#  task_type(机器端任务类型（nurture/fetch/send_message/check_reply/5 个 publish）) :string(255)
#  created_at                                                                       :datetime         not null
#  updated_at                                                                       :datetime         not null
#  machine_task_id(机器端返回的 task_id)                                            :string(255)      not null
#
# Indexes
#
#  index_browser_task_records_on_created_at       (created_at)
#  index_browser_task_records_on_machine_task_id  (machine_task_id) UNIQUE
#  index_browser_task_records_on_status           (status)
#
class BrowserTaskRecord < ApplicationRecord
  # 本地记录状态
  STATUS_PENDING = 'pending'.freeze
  STATUS_SUCCESS = 'success'.freeze
  STATUS_FAILED  = 'failed'.freeze
  STATUS_UNKNOWN = 'unknown'.freeze

  validates :machine_task_id, presence: true, uniqueness: true

  # 任务类型可读标签（与机器端 task_type 枚举对应）
  TASK_TYPE_LABELS = {
    'nurture'           => '养号',
    'fetch'             => '采集',
    'send_message'      => '发私信',
    'check_reply'       => '检查回复',
    'facebook_publish'  => 'Facebook发布',
    'twitter_publish'   => 'X发布',
    'youtube_publish'   => 'YouTube发布',
    'tiktok_publish'    => 'TikTok发布',
    'instagram_publish' => 'Instagram发布'
  }.freeze

  STATUS_LABELS = {
    STATUS_PENDING => '执行中',
    STATUS_SUCCESS => '成功',
    STATUS_FAILED  => '失败',
    STATUS_UNKNOWN => '已丢失'
  }.freeze

  scope :pending, -> { where(status: STATUS_PENDING) }

  # 供后台列表展示用：任务类型的可读名称
  def task_type_label
    TASK_TYPE_LABELS[task_type] || task_type.to_s
  end

  def status_label
    STATUS_LABELS[status] || status.to_s
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id machine_task_id ref task_type profile_name machine_ip status message created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[]
  end

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
