# == Schema Information
#
# Table name: themes
#
#  id            :bigint           not null, primary key
#  name          :string(255)      not null
#  oss_directory :string(255)
#  remark        :text(65535)
#  titles        :text(65535)
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
# Indexes
#
#  index_themes_on_name           (name) UNIQUE
#  index_themes_on_oss_directory  (oss_directory) UNIQUE
#
class Theme < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  before_save :convert_empty_strings_to_null

  def convert_empty_strings_to_null
    self.oss_directory = nil if oss_directory.blank?
    self.titles = nil if titles.blank?
    self.remark = nil if remark.blank?
  end

  def titles_array
    return [] unless titles.present?
    titles.split("\n").map(&:strip).reject(&:empty?)
  end

  def self.all_names
    pluck(:name)
  end
end
