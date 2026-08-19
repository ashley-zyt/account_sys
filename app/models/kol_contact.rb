# == Schema Information
#
# Table name: kol_contacts
#
#  id                 :bigint           not null, primary key
#  kol_id             :bigint           not null
#  last_used_at       :datetime
#  messaging_enabled  :boolean          default(FALSE), not null
#  nickname           :string(255)
#  platform           :integer          not null
#  priority           :integer          default(0), not null
#  status             :integer          default("active")
#  url                :string(255)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
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
