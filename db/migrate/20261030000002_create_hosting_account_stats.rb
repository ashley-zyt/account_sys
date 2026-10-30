# 托管账号监控日快照（与 account_stat 结构对齐，归属 hosting_account_id）。
# 托管账号走外部采集系统，数据独立存储，不污染普通账号的 account_stat/post_stats。
class CreateHostingAccountStats < ActiveRecord::Migration[6.1]
  def change
    create_table :hosting_account_stats, comment: '托管账号监控日快照' do |t|
      t.bigint   :hosting_account_id, null: false, comment: '托管账号ID'
      t.date     :stat_date,          null: false, comment: '统计日期'
      t.bigint   :followers_count,    comment: '粉丝数'
      t.bigint   :total_posts,        comment: '发帖数'
      t.bigint   :total_views,        comment: '总浏览量'
      t.bigint   :total_likes,        comment: '总点赞数'
      t.bigint   :total_comments,     comment: '总评论数'
      t.bigint   :total_shares,       comment: '总分享数'
      t.datetime :snapshot_at,        comment: '快照时间'
      t.timestamps
    end

    add_index :hosting_account_stats, [:hosting_account_id, :stat_date], unique: true, name: 'index_hosting_account_stats_on_account_and_date'
    add_index :hosting_account_stats, :stat_date
  end
end
