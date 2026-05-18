class KolPlatformAccount < ApplicationRecord
  belongs_to :kol

  has_many :conversations, dependent: :destroy

  enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		instagram: 5
	}

  validates :platform, presence: true
  validates :nick_name, presence: true
end