class MessageTemplateVariable < ApplicationRecord
  belongs_to :message_template
  belongs_to :message_variable

  validates :message_variable_id, uniqueness: { scope: :message_template_id }
end
