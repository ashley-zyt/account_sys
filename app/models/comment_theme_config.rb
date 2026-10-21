# == Schema Information
#
# Table name: comment_theme_configs
#
#  id                                                     :bigint           not null, primary key
#  prompt(评论互动 prompt（每行一条）)                    :text(65535)
#  theme(主题名（对应 Account.theme / Influencer.theme）) :string(255)      not null
#  created_at                                             :datetime         not null
#  updated_at                                             :datetime         not null
#
# Indexes
#
#  index_comment_theme_configs_on_theme  (theme) UNIQUE
#
class CommentThemeConfig < ApplicationRecord
  validates :theme, presence: true, uniqueness: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme prompt created_at updated_at]
  end
end
