class ConversationMessage < ApplicationRecord
  belongs_to :conversation

  enum :sender_type, {
    social_account: 0,
    kol: 1
  }

  validates :sender_type, presence: true
  validates :content, presence: true
end