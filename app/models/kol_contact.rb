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
#  status(联系方式状态：active/invalid)  :integer          default("active"), not null
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
    active: 0,
    invalid: 1
  }

  validates :platform, presence: true

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
