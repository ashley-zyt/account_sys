# == Schema Information
#
# Table name: message_variables
#
#  id                                      :bigint           not null, primary key
#  description(变量说明)                   :text(65535)
#  identifier(变量标识符（如 name/email）) :string(255)      not null
#  name(变量中文名)                        :string(255)      not null
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#
# Indexes
#
#  index_message_variables_on_identifier  (identifier) UNIQUE
#
class MessageVariable < ApplicationRecord
  has_many :message_template_variables, dependent: :destroy
  has_many :message_templates, through: :message_template_variables

  validates :identifier, presence: true, uniqueness: true
  validates :name, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id identifier name description created_at updated_at]
  end
end
