# == Schema Information
#
# Table name: conversation_messages
#
#  id                      :bigint           not null, primary key
#  content(消息内容)       :text(65535)      not null
#  sender_type(发送方类型) :integer          not null
#  sent_at(发送时间)       :datetime
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  conversation_id(会话ID) :bigint           not null
#
# Indexes
#
#  index_conversation_messages_on_conversation_id  (conversation_id)
#  index_conversation_messages_on_sender_type      (sender_type)
#  index_conversation_messages_on_sent_at          (sent_at)
#
# Foreign Keys
#
#  fk_rails_...  (conversation_id => conversations.id)
#
class ConversationMessage < ApplicationRecord
  belongs_to :conversation

  enum sender_type: {
    social_account: 0,
    kol: 1
  }

  validates :sender_type, presence: true
  validates :content, presence: true
end
