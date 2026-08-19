# == Schema Information
#
# Table name: kol_messages
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint
#  content             :text(65535)
#  direction           :integer          default("outgoing"), not null
#  error_msg           :text(65535)
#  is_auto_reply       :boolean          default(FALSE), not null
#  kol_contact_id      :bigint
#  kol_id              :bigint           not null
#  message_template_id :bigint
#  occurred_at         :datetime
#  platform            :integer          not null
#  source              :integer          default("auto"), not null
#  status              :integer          default("queued")
#  wait_until          :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#
class KolMessage < ApplicationRecord
  belongs_to :kol
  belongs_to :kol_contact, optional: true
  belongs_to :account, optional: true
  belongs_to :message_template, optional: true

  enum direction: {
    outgoing: 0,   # 我方发出
    incoming: 1    # 对方回复
  }

  enum source: {
    auto: 0,       # 自动化
    manual: 1      # 人工
  }

  # 平台/渠道（与 KolContact.platform 数值保持一致）
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

  # 第二层：会话执行状态
  enum status: {
    queued: 0,        # 待发送
    sent_success: 1,  # 发送成功
    sent_failed: 2,   # 发送失败
    replied: 3,       # 已回复
    ignored: 4        # 已放弃
  }

  validates :kol_id, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id kol_id kol_contact_id account_id message_template_id platform
      direction source status error_msg occurred_at wait_until is_auto_reply
      created_at updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol kol_contact account message_template]
  end
end
