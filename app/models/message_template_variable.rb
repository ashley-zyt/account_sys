# == Schema Information
#
# Table name: message_template_variables
#
#  id                  :bigint           not null, primary key
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  message_template_id :bigint           not null
#  message_variable_id :bigint           not null
#
# Indexes
#
#  index_message_template_variables_on_message_template_id  (message_template_id)
#  index_message_template_variables_on_message_variable_id  (message_variable_id)
#  index_mtvars_on_template_and_variable                    (message_template_id,message_variable_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (message_template_id => message_templates.id)
#  fk_rails_...  (message_variable_id => message_variables.id)
#
class MessageTemplateVariable < ApplicationRecord
  belongs_to :message_template
  belongs_to :message_variable

  validates :message_variable_id, uniqueness: { scope: :message_template_id }
end
