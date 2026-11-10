# 评论互动：支持给指定主题配置「额外参与账号」（跨主题）。
# 这些账号 theme 与主题不一致，但想参与该主题大V的评论互动（例如通用账号 934）。
# 存逗号分隔的账号 id，CommentScheduler.themed_accounts 会把它们并入候选账号池。
class AddExtraAccountIdsToCommentThemeConfigs < ActiveRecord::Migration[6.1]
  def change
    add_column :comment_theme_configs, :extra_account_ids, :string,
               comment: '额外参与该主题评论互动的账号 id（逗号分隔，可跨主题）'
  end
end
