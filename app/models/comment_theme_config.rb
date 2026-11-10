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

  # 解析额外参与账号 id（逗号分隔），返回去重后的整数数组
  def extra_account_ids_list
    extra_account_ids.to_s.split(',').map(&:strip).reject(&:empty?).map(&:to_i).reject(&:zero?).uniq
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme prompt extra_account_ids created_at updated_at]
  end
end
