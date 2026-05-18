class SocialAccount < ApplicationRecord
  enum platform: {
    facebook: 1,
    twitter: 2,
    tiktok: 3,
    youtube: 4,
    instagram: 5
  }

  has_many :conversations, dependent: :destroy

  validates :nick_name, presence: true
  validates :platform, presence: true
end