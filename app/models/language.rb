class Language < ApplicationRecord
  has_many :kols
  has_many :message_template_versions

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id code name created_at updated_at]
  end
end
