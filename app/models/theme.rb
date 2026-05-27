class Theme < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  def titles_array
    return [] unless titles.present?
    titles.split("\n").map(&:strip).reject(&:empty?)
  end

  def self.all_names
    pluck(:name)
  end
end
