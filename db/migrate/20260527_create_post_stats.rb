class CreatePostStats < ActiveRecord::Migration[6.1]
  def change
    create_table :post_stats do |t|
      t.bigint :account_id, null: false, comment: '账号ID'
      t.date :post_date, null: false, comment: '发文日期'
      t.string :title, comment: '发文标题'
      t.string :url, comment: '发文链接'
      t.integer :likes_count, default: 0, comment: '点赞数量'
      t.integer :shares_count, default: 0, comment: '转发数量'
      t.integer :comments_count, default: 0, comment: '评论数量'
      t.integer :views_count, default: 0, comment: '浏览数量'
      t.datetime :data_updated_at, comment: '数据更新时间'

      t.timestamps
    end

    add_index :post_stats, :account_id
    add_index :post_stats, :post_date
  end
end