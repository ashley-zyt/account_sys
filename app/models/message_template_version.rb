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

  # 用 KOL 的变量值替换 ${variable} 占位符。
  # 规则：
  #   - 变量 key 不区分大小写匹配（${name} 与 ${NAME} 等价）
  #   - NAME 变量（KOL名称）为空时，自动回退使用 KOL 的 name 字段
  def render_content(kol)
    content.to_s.gsub(/\$\{(\w+)\}/) do
      key = Regexp.last_match(1)
      value = kol.variable_value(key)
      value = kol.variable_value(key.upcase) if value.blank? && key != key.upcase
      value = kol.variable_value(key.downcase) if value.blank? && key != key.downcase
      value = kol.name if value.blank? && key.casecmp?("NAME")
      value.to_s
    end
  end
end
