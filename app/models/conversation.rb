# == Schema Information
#
# Table name: conversations
#
#  id                                     :bigint           not null, primary key
#  closed_at(关闭时间)                    :datetime
#  last_message_at(最后消息时间)          :datetime
#  latest_message(最新消息摘要)           :text(65535)
#  platform(平台)                         :integer          not null
#  status(会话状态)                       :integer          default(0), not null
#  created_at                             :datetime         not null
#  updated_at                             :datetime         not null
#  kol_id(KOL ID)                         :bigint           not null
#  kol_platform_account_id(KOL平台账号ID) :bigint           not null
#  social_account_id(运营账号ID)          :bigint           not null
#
# Indexes
#
#  index_conversations_on_kol_id                   (kol_id)
#  index_conversations_on_kol_platform_account_id  (kol_platform_account_id)
#  index_conversations_on_last_message_at          (last_message_at)
#  index_conversations_on_platform                 (platform)
#  index_conversations_on_social_account_id        (social_account_id)
#  index_conversations_on_status                   (status)
#
class Conversation < ApplicationRecord
  belongs_to :kol
  belongs_to :kol_platform_account
  belongs_to :account

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
