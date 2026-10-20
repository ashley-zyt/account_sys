# 给大V发文表加「发文链接」字段（对应 API 返回的 source_url，用于跳转原文）
class AddSourceUrlToInfluencerPosts < ActiveRecord::Migration[6.1]
  def change
    add_column :influencer_posts, :source_url, :string, comment: '发文链接'
  end
end
