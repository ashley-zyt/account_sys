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
