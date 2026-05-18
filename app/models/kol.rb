# == Schema Information
#
# Table name: kols
#
#  id                :bigint           not null, primary key
#  category(类别)    :string(255)
#  kol_name(KOL名称) :string(255)      not null
#  location(地区)    :string(255)
#  nick_name(昵称)   :string(255)
#  notes(备注)       :text(65535)
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_kols_on_category  (category)
#  index_kols_on_kol_name  (kol_name)
#
class Kol < ApplicationRecord
  has_many :kol_platform_accounts, dependent: :destroy
  has_many :conversations, dependent: :destroy

  accepts_nested_attributes_for :kol_platform_accounts, allow_destroy: true, reject_if: ->(attrs) { attrs['platform'].blank? && attrs['nick_name'].blank? }

  validates :kol_name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    ["category", "created_at", "id", "kol_name", "location", "nick_name", "notes", "updated_at"]
  end

  def self.ransackable_associations(auth_object = nil)
    ["kol_platform_accounts", "conversations"]
  end
end
