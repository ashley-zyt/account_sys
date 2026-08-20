# == Schema Information
#
# Table name: themes
#
#  id            :bigint           not null, primary key
#  name          :string(255)      not null
#  oss_directory :string(255)
#  prompts       :text(65535)
#  remark        :text(65535)
#  titles        :text(65535)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  domain_id     :bigint
#
# Indexes
#
#  index_themes_on_domain_id      (domain_id)
#  index_themes_on_name           (name) UNIQUE
#  index_themes_on_oss_directory  (oss_directory) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (domain_id => domains.id)
#
class Theme < ApplicationRecord
  belongs_to :domain, optional: true

  validates :name, presence: { message: '主题名称不能为空' }, uniqueness: { message: '该主题名称已存在' }

  before_save :convert_empty_strings_to_null

  def convert_empty_strings_to_null
    self.oss_directory = nil if oss_directory.blank?
    self.titles = nil if titles.blank?
    self.prompts = nil if prompts.blank?
    self.remark = nil if remark.blank?
  end

  def prompts_array
    return [] unless prompts.present?
    prompts.split("\n").map(&:strip).reject(&:empty?)
  end

  def titles_array
    return [] unless titles.present?
    titles.split("\n").map(&:strip).reject(&:empty?)
  end

  def self.all_names
    pluck(:name)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name domain_id oss_directory titles prompts remark created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[domain]
  end
end
