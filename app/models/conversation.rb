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
#  account_id(运营账号ID)                :bigint           not null
#
# Indexes
#
#  index_conversations_on_kol_id                   (kol_id)
#  index_conversations_on_kol_platform_account_id  (kol_platform_account_id)
#  index_conversations_on_last_message_at          (last_message_at)
#  index_conversations_on_platform                 (platform)
#  index_conversations_on_account_id               (account_id)
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

  enum status: {
    "待发送": 0,#会话创建了但还没真正发消息
    "已联系": 1,#已发送私信,等待回复
    "已回复": 2,#对方已经回复消息
    "已合作": 3,#已确认合作
    "已拒绝": 5,#对方明确拒绝
    "已关闭": 6#人工结束会话
  }

  validates :platform, presence: true
  validates :status, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["account_id", "closed_at", "created_at", "id", "kol_id", "kol_platform_account_id", "last_message_at", "latest_message", "platform", "status", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["kol", "kol_platform_account", "account", "conversation_messages"]
  end
end
