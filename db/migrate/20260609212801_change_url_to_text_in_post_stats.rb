class ChangeUrlToTextInPostStats < ActiveRecord::Migration[6.1]
  def change
    # 先删除唯一索引
    remove_index :post_stats, name: 'index_post_stats_on_url'
    
    # 修改列类型
    change_column :post_stats, :url, :text
    
    # 重新添加唯一索引（使用前缀长度，MySQL TEXT 类型索引需要指定前缀）
    # 使用 255 作为前缀长度，这是 MySQL 唯一索引的最大允许值
    execute 'CREATE UNIQUE INDEX index_post_stats_on_url ON post_stats (url(255))'
  end
end