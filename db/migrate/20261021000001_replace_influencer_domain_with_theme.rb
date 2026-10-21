# 大V评论互动：领域(domain)粒度改成主题(theme)粒度
#   - 移除 influencers.domain_id（领域）
#   - 新增 influencers.theme（主题名，对应 themes.name，决定评论账号与 prompt）
class ReplaceInfluencerDomainWithTheme < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :influencers, :domains, if_exists: true
    remove_column :influencers, :domain_id, :bigint, if_exists: true
    add_column :influencers, :theme, :string, comment: '主题名（对应 themes.name，决定评论账号与 prompt）'
    add_index :influencers, :theme
  end
end
