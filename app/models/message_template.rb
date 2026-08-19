# == Schema Information
#
# Table name: message_templates
#
#  id                                :bigint           not null, primary key
#  content(模板内容（支持变量注入）) :text(65535)      not null
#  language(语种)                    :string(255)      default("en"), not null
#  name(模板名称)                    :string(255)      not null
#  scenario(模板场景)                :integer          default("first_contact"), not null
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#
# Indexes
#
#  index_message_templates_on_scenario_and_language  (scenario,language)
#
class MessageTemplate < ApplicationRecord
  has_many :kol_messages, dependent: :nullify

  # 场景分类：首次建联 / 跟进询问
  enum scenario: {
    first_contact: 0,
    follow_up: 1
  }

  validates :name, presence: true
  validates :language, presence: true
  validates :content, presence: true

  # 按场景 + 语种匹配模板（取最早创建的一条，语种大小写不敏感）
  def self.for(scenario:, language:)
    where(scenario: scenario)
      .where("LOWER(language) = ?", language.to_s.downcase)
      .order(:id)
      .first
  end

  # 变量注入：发送时替换为真实数据
  # 支持变量：${kol_name} / ${account_name} / ${sender_account} / ${owner} / ${nickname} / ${platform}
  def render_with(kol: nil, account: nil, contact: nil)
    text = content.to_s
    text = text.gsub(/\$\{kol_name\}/, kol&.name.to_s)
    # 约定：${account_name} 指被触达方的称呼（KOL 名称）
    text = text.gsub(/\$\{account_name\}/, kol&.name.to_s)
    text = text.gsub(/\$\{sender_account\}/, account&.account_name.to_s)
    text = text.gsub(/\$\{owner\}/, kol&.owner.to_s)
    text = text.gsub(/\$\{nickname\}/, contact&.nickname.to_s)
    text = text.gsub(/\$\{platform\}/, contact&.platform.to_s)
    text
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name scenario language content created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[kol_messages]
  end
end
