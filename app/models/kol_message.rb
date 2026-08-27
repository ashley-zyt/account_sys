# == Schema Information
#
# Table name: kol_messages
#
#  id                                      :bigint           not null, primary key
#  content(消息内容)                       :text(65535)
#  direction(消息方向)                     :integer          default("outgoing"), not null
#  error_msg(失败原因)                     :text(65535)
#  is_auto_reply(是否为自动回复（假回复）) :boolean          default(FALSE), not null
#  occurred_at(消息发生时间)               :datetime
#  platform(平台/渠道)                     :integer          not null
#  source(消息来源)                        :integer          default("auto"), not null
#  status(会话执行状态)                    :integer          default("queued"), not null
#  wait_until(等待回复截止时间)            :datetime
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#  account_id                              :bigint
#  kol_contact_id                          :bigint
#  kol_id                                  :bigint           not null
#  message_template_id                     :bigint
#
# Indexes
#
#  index_kol_messages_on_account_id           (account_id)
#  index_kol_messages_on_direction            (direction)
#  index_kol_messages_on_kol_contact_id       (kol_contact_id)
#  index_kol_messages_on_kol_id               (kol_id)
#  index_kol_messages_on_message_template_id  (message_template_id)
#  index_kol_messages_on_occurred_at          (occurred_at)
#  index_kol_messages_on_status               (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (kol_contact_id => kol_contacts.id)
#  fk_rails_...  (kol_id => kols.id)
#  fk_rails_...  (message_template_id => message_templates.id)
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

  # 是否为「首次联系」的失败尝试（自动触达 + 发送失败）
  # 这类噪音消息在对话流里折叠展示，主流程只保留成功发送与后续跟进
  def first_contact_failure?
    auto? && sent_failed?
  end
end
