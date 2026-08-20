# == Schema Information
#
# Table name: message_templates
#
#  id                             :bigint           not null, primary key
#  name(模板名称)                 :string(255)      not null
#  platform(适用平台（空为通用）) :integer
#  scenario(模板场景)             :integer          default("first_contact"), not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  domain_id                      :bigint
#
# Indexes
#
#  index_message_templates_on_domain_id  (domain_id)
#
# Foreign Keys
#
#  fk_rails_...  (domain_id => domains.id)
#
class MessageTemplate < ApplicationRecord
  belongs_to :domain

  has_many :message_template_versions, dependent: :destroy
  has_many :message_template_variables, dependent: :destroy
  has_many :message_variables, through: :message_template_variables

  accepts_nested_attributes_for :message_template_versions, allow_destroy: true, reject_if: :all_blank

  enum scenario: {
    first_contact: 0,        # 首次建联
    follow_up: 1,            # 跟进询问
    follow_up_again: 2,      # 再次跟进
    cooperation_quote: 3,    # 合作邀请/报价
    relationship_maintain: 4 # 关系维护/感谢
  }

  # 场景中文标签（下拉与展示共用）
  SCENARIOS = {
    "first_contact"        => "首次建联",
    "follow_up"            => "跟进询问",
    "follow_up_again"      => "再次跟进",
    "cooperation_quote"    => "合作邀请/报价",
    "relationship_maintain" => "关系维护/感谢"
  }.freeze

  def scenario_label
    SCENARIOS[scenario] || scenario.to_s
  end

  # 平台（空 = 通用）
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

  validates :name, presence: true
  validates :scenario, presence: true

  # 取指定语言的版本，找不到则回退到任意版本
  def version_for(language_id)
    message_template_versions.find_by(language_id: language_id) || message_template_versions.first
  end

  # 模板所需变量标识符列表
  def required_variable_keys
    message_variables.map(&:identifier)
  end

  # 用 KOL 变量值渲染模板（按 KOL 语言选版本）
  def render_for(kol)
    version_for(kol.language_id)&.render_content(kol)
  end

  # 匹配主模板：scenario + platform（空=通用）+ domain（空=通用）
  def self.match_for(scenario:, platform: nil, domain_id: nil)
    scope = where(scenario: scenario)

    if platform.present?
      pval = platform_value(platform)
      scope = scope.where("platform IS NULL OR platform = ?", pval)
    else
      scope = scope.where(platform: nil)
    end

    scope = scope.where(domain_id: domain_id) if domain_id.present?
    scope
  end

  # 录入 KOL 时按「平台 + 领域」软提示可能需要的变量（取并集）
  def self.suggested_variables(scenario:, platforms: [], domain_id: nil)
    pvals = Array(platforms).map { |p| platform_value(p) }.compact
    scope = where(scenario: scenario)
    scope = scope.where("platform IS NULL OR platform IN (?)", pvals) if pvals.any?
    scope = scope.where(domain_id: domain_id) if domain_id.present?
    scope.includes(:message_variables).flat_map { |t| t.message_variables.map(&:identifier) }.uniq
  end

  def self.platform_value(platform)
    return platform if platform.is_a?(Integer)
    platforms[platform.to_s]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name scenario platform domain_id created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[domain message_template_versions message_variables]
  end
end
