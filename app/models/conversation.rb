class Conversation < ApplicationRecord
  belongs_to :kol
  belongs_to :kol_platform_account
  belongs_to :social_account

  has_many :conversation_messages, dependent: :destroy

  enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		instagram: 5
	}

  enum :status, {
    pending: 0,
    contacted: 1,
    replied: 2,
    negotiating: 3,
    cooperated: 4,
    rejected: 5,
    closed: 6
  }

  validates :platform, presence: true
  validates :status, presence: true
end