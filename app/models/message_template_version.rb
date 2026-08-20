# == Schema Information
#
# Table name: message_template_versions
#
#  id                                     :bigint           not null, primary key
#  content(模板内容（支持 ${变量} 注入）) :text(65535)      not null
#  created_at                             :datetime         not null
#  updated_at                             :datetime         not null
#  language_id                            :bigint           not null
#  message_template_id                    :bigint           not null
#
# Indexes
#
#  index_message_template_versions_on_language_id          (language_id)
#  index_message_template_versions_on_message_template_id  (message_template_id)
#  index_mtv_on_template_and_language                      (message_template_id,language_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (language_id => languages.id)
#  fk_rails_...  (message_template_id => message_templates.id)
#
class MessageTemplateVersion < ApplicationRecord
  belongs_to :message_template
  belongs_to :language

  validates :content, presence: true
  validates :language_id, uniqueness: { scope: :message_template_id }

  # 用 KOL 的变量值替换 ${variable} 占位符
  def render_content(kol)
    content.to_s.gsub(/\$\{(\w+)\}/) { kol.variable_value($1).to_s }
  end
end
