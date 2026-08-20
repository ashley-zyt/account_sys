# == Schema Information
#
# Table name: languages
#
#  id                           :bigint           not null, primary key
#  code(语言代码（zh/en/ja…）) :string(255)      not null
#  name(语言中文名)             :string(255)      not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# Indexes
#
#  index_languages_on_code  (code) UNIQUE
#
class Language < ApplicationRecord
  has_many :kols
  has_many :message_template_versions

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id code name created_at updated_at]
  end
end
