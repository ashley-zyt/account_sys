class CreateAccountStats < ActiveRecord::Migration[6.1]
  def change
    create_table :account_stats, comment: '账号日维度总量快照（粉丝/浏览/点赞/发帖数）' do |t|
      t.bigint :account_id, null: false, comment: '账号ID'
      t.date :stat_date, null: false, comment: '统计日期（快照所属的自然日）'
      t.integer :followers_count, default: 0, comment: '总粉丝数（截止当前）'
      t.integer :total_views_count, default: 0, comment: '总浏览量（所有发文累计）'
      t.integer :total_likes_count, default: 0, comment: '总点赞量（所有发文累计）'
      t.integer :total_comments_count, default: 0, comment: '总评论量（所有发文累计）'
      t.integer :total_shares_count, default: 0, comment: '总转发量（所有发文累计）'
      t.integer :total_posts_count, default: 0, comment: '总发帖量（截止当前）'
      t.datetime :snapshot_at, comment: '快照采集时间（采集接口返回的时刻）'

      t.timestamps
    end

    # 复合唯一索引：一个账号同一天只能有一条快照
    add_index :account_stats, [:account_id, :stat_date], unique: true
    # 用于按日期范围查询某个账号的趋势
    add_index :account_stats, :stat_date
    # 用于全局趋势（按平台/主题聚合时先查账号再关联）
    add_index :account_stats, :account_id
  end
end
