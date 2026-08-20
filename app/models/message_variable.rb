class MessageVariable < ApplicationRecord
  has_many :message_template_variables, dependent: :destroy
  has_many :message_templates, through: :message_template_variables

  validates :identifier, presence: true, uniqueness: true
  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id identifier name description created_at updated_at]
  end
end
