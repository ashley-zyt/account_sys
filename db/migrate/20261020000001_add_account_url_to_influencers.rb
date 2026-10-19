# 给大V表加「账号链接」字段（大V账号主页链接，用于评论互动时定位目标账号）
class AddAccountUrlToInfluencers < ActiveRecord::Migration[6.1]
  def change
    add_column :influencers, :account_url, :string, comment: '账号链接'
  end
end
