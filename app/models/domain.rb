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
