# == Schema Information
#
# Table name: kol_contacts
#
#  id                                    :bigint           not null, primary key
#  last_used_at(最后使用时间)            :datetime
#  messaging_enabled(是否可作为发信渠道) :boolean          default(FALSE), not null
#  nickname(平台昵称/账号)               :string(255)
#  platform(平台或通讯渠道)              :integer          not null
#  priority(触达优先级（越小越优先）)    :integer          default(0), not null
#  status(联系方式状态：active/disabled)  :integer          default("active"), not null
#  url(主页链接或联系方式)               :string(255)
#  created_at                            :datetime         not null
#  updated_at                            :datetime         not null
#  kol_id                                :bigint           not null
#
# Indexes
#
#  index_kol_contacts_on_kol_id    (kol_id)
#  index_kol_contacts_on_platform  (platform)
#  index_kol_contacts_on_priority  (priority)
#  index_kol_contacts_on_status    (status)
#
# Foreign Keys
#
#  fk_rails_...  (kol_id => kols.id)
#
class KolContact < ApplicationRecord
  belongs_to :kol
  has_many :kol_messages, dependent: :nullify

  # 平台/渠道枚举（社交平台 1-5 与内部 Account.platform 数值保持一致，便于映射）
  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5,
    email: 6,
    telegram: 7,
    whatsapp: 8
  }

  enum status: {
    active: 0,       # 可用（尚未联系）
    disabled: 1,     # 停用（人工关闭）
    contacting: 2,   # 已联系，等回复（30 天窗口内）
    replied: 3,      # 已回复
    unresponsive: 4  # 未回复（30 天窗口到期仍无回复）
  }

  # 联系方式状态中文标签（展示用）
  STATUS_LABELS = {
    "active"       => "未联系",
    "disabled"     => "已停用",
    "contacting"   => "已联系·等回复",
    "replied"      => "已回复",
    "unresponsive" => "未回复"
  }.freeze

  def status_label
    STATUS_LABELS[status] || status.to_s
  end

  validates :platform, presence: true

  # 该联系方式最后一次「发送成功」所用的内部账号（用于 check_reply / 人工回复）
  def last_outgoing_account
    kol_messages
      .where(direction: KolMessage.directions[:outgoing], status: KolMessage.statuses[:sent_success])
      .where.not(account_id: nil)
      .order(id: :desc)
      .first&.account
  end

  # 是否仍在回复监测窗口内
  def monitoring?
    contacting? && monitor_until.present? && monitor_until > Time.current
  end

  # 是否为内部社交账号平台（可调用内部账号发送私信）
  def social_platform?
    %w[facebook twitter tiktok youtube instagram].include?(platform)
  end

  # 平台展示图标（多平台名片夹 / 对话流气泡旁使用）
  def platform_icon
    {
      "facebook" => "📘",
      "twitter" => "🐦",
      "tiktok" => "🎵",
      "youtube" => "▶️",
      "instagram" => "📷",
      "email" => "📧",
      "telegram" => "✈️",
      "whatsapp" => "💬"
    }[platform.to_s] || "🔗"
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id kol_id platform nickname url priority messaging_enabled
      status last_used_at created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol]
  end
end
