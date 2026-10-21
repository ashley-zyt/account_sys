# == Schema Information
#
# Table name: comment_theme_configs
#
#  id         :bigint           not null, primary key
#  theme      :string(255)      not null
#  prompt     :text(65535)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_comment_theme_configs_on_theme  (theme) UNIQUE
#
class CommentThemeConfig < ApplicationRecord
  validates :theme, presence: true, uniqueness: true

  # 每行一条 prompt（评论生成时逐条作为背景/要求注入）
  def prompt_array
    return [] unless prompt.present?
    prompt.split("\n").map(&:strip).reject(&:empty?)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme prompt created_at updated_at]
  end
end
