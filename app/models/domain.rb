# == Schema Information
#
# Table name: domains
#
#  id                                 :bigint           not null, primary key
#  name(领域名称（文旅/金融/科技…）) :string(255)      not null
#  created_at                         :datetime         not null
#  updated_at                         :datetime         not null
#
# Indexes
#
#  index_domains_on_name  (name) UNIQUE
#
class Domain < ApplicationRecord
  has_many :kols
  has_many :themes
  has_many :message_templates

  validates :name, presence: true, uniqueness: true

  # 按名称查找或创建（同名自动去重）
  def self.find_or_create_by_name(name)
    n = name.to_s.strip
    return nil if n.blank?
    find_or_create_by!(name: n)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id name created_at updated_at]
  end
end
