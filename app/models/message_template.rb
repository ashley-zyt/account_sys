class MessageTemplate < ApplicationRecord
  enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		instagram: 5
	}

  enum :template_type, {
    first_contact: 0,
    follow_up: 1,
    reply: 2,
    cooperation: 3,
    closing: 4
  }

  validates :platform, presence: true
  validates :template_type, presence: true
  validates :content, presence: true
end