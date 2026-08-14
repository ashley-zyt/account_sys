# == Schema Information
#
# Table name: account_stats
#
#  id                                              :bigint           not null, primary key
#  followers_count(总粉丝数（截止当前）)           :integer          default(0)
#  snapshot_at(快照采集时间（采集接口返回的时刻）) :datetime
#  stat_date(统计日期（快照所属的自然日）)         :date             not null
#  total_comments_count(总评论量（所有发文累计）)  :integer          default(0)
#  total_likes_count(总点赞量（所有发文累计）)     :integer          default(0)
#  total_posts_count(总发帖量（截止当前）)         :integer          default(0)
#  total_shares_count(总转发量（所有发文累计）)    :integer          default(0)
#  total_views_count(总浏览量（所有发文累计）)     :integer          default(0)
#  created_at                                      :datetime         not null
#  updated_at                                      :datetime         not null
#  account_id(账号ID)                              :bigint           not null
#
# Indexes
#
#  index_account_stats_on_account_id                (account_id)
#  index_account_stats_on_account_id_and_stat_date  (account_id,stat_date) UNIQUE
#  index_account_stats_on_stat_date                 (stat_date)
#

class AccountStat < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true
  validates :stat_date, presence: true, uniqueness: { scope: :account_id }

  validates :followers_count,      numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_views_count,    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_likes_count,    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_comments_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_shares_count,   numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :total_posts_count,    numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_account,   ->(account_id) { where(account_id: account_id) }
  scope :by_date_range, ->(start_date, end_date) { where(stat_date: start_date..end_date) }
  scope :order_by_date, -> { order(stat_date: :desc) }

  # === 常用统计类方法 ===

  # 查询指定账号在某个时间范围内的趋势数据（按日期升序，用于画折线）
  # @return [Array<AccountStat>]
  def self.trend_for_account(account_id, start_date, end_date)
    by_account(account_id)
      .by_date_range(start_date, end_date)
      .order(stat_date: :asc)
  end

  # 查询某个账号最近 N 条快照（按日期倒序）
  # @return [Array<AccountStat>]
  def self.recent_for_account(account_id, limit = 30)
    by_account(account_id).order_by_date.limit(limit)
  end

  # 两个快照之间的增量对比
  # @return [Hash, nil] { views_delta:, likes_delta:, comments_delta:, shares_delta:, posts_delta:, followers_delta: }
  def delta_from(other)
    return nil unless other.is_a?(AccountStat)
    {
      views_delta:     total_views_count.to_i    - other.total_views_count.to_i,
      likes_delta:     total_likes_count.to_i    - other.total_likes_count.to_i,
      comments_delta:  total_comments_count.to_i - other.total_comments_count.to_i,
      shares_delta:    total_shares_count.to_i   - other.total_shares_count.to_i,
      posts_delta:     total_posts_count.to_i    - other.total_posts_count.to_i,
      followers_delta: followers_count.to_i      - other.followers_count.to_i,
      days_diff:       (stat_date - other.stat_date).to_i
    }
  end

  # 计算日均增量（相对于上一条快照）
  # @return [Hash, nil]
  def daily_average_delta
    previous = AccountStat.by_account(account_id)
                          .where('stat_date < ?', stat_date)
                          .order(stat_date: :desc)
                          .first
    return nil unless previous

    delta = delta_from(previous)
    days  = [delta[:days_diff], 1].max
    {
      avg_views:     (delta[:views_delta].to_f     / days).round(1),
      avg_likes:     (delta[:likes_delta].to_f     / days).round(1),
      avg_comments:  (delta[:comments_delta].to_f  / days).round(1),
      avg_shares:    (delta[:shares_delta].to_f    / days).round(1),
      avg_posts:     (delta[:posts_delta].to_f     / days).round(1),
      avg_followers: (delta[:followers_delta].to_f / days).round(1),
      days_covered:  days
    }
  end

  # === 数据落库入口 ===

  # 从 post_stats 表反推一个账号当日的累计快照
  # 采集端返回的 total_followers / total_posts 可直接传入，缺失则用历史数据聚合
  #
  # 字段处理策略：
  # - followers_count (总粉丝数)：所有平台均使用采集端返回值。传入则用，没传则复用最近一条快照值。
  # - total_posts_count (总发帖量)：
  #     * YouTube / Instagram 平台：使用采集端返回的 total_posts
  #     * 其他平台（Facebook/Twitter/TikTok）：始终用 post_stats COUNT(*) 聚合
  # - total_likes_count (总点赞数)：所有平台始终用 post_stats 聚合，不使用API返回值
  # - 其他累计字段（views/comments/shares）始终用 post_stats 聚合
  #
  # @param account_id      [Integer]
  # @param stat_date       [Date]
  # @param followers_count [Integer, nil] 采集端 total_followers
  # @param total_posts     [Integer, nil] 采集端 total_posts（仅 YouTube/Instagram 使用）
  # @param snapshot_at     [DateTime, nil]
  # @return [AccountStat, nil]
  def self.upsert_from_post_stats!(account_id, stat_date = Date.today, followers_count: nil, total_posts: nil, snapshot_at: nil)
    account = Account.find_by(id: account_id)
    return nil unless account

    base_scope = account.post_stats

    aggregated = base_scope.pick(
      Arel.sql('COUNT(*)'),
      Arel.sql('COALESCE(SUM(views_count), 0)'),
      Arel.sql('COALESCE(SUM(likes_count), 0)'),
      Arel.sql('COALESCE(SUM(comments_count), 0)'),
      Arel.sql('COALESCE(SUM(shares_count), 0)')
    )
    posts_count, views_sum, likes_sum, comments_sum, shares_sum = aggregated

    # 粉丝数：所有平台均使用采集端返回值，否则复用上次快照
    final_followers =
      if followers_count.present?
        followers_count.to_i
      else
        prev = AccountStat.by_account(account_id).order_by_date.first
        prev ? prev.followers_count.to_i : 0
      end

    # 总发帖量：YouTube/Instagram 用API返回值，其他平台用 post_stats COUNT(*)
    use_api_total_posts = account.youtube? || account.instagram?
    final_total_posts =
      if use_api_total_posts && total_posts.present?
        total_posts.to_i
      else
        posts_count.to_i
      end

    # 总点赞：所有平台始终用 post_stats 聚合，不使用API返回值
    final_total_likes = likes_sum.to_i

    attrs = {
      followers_count:      final_followers,
      total_views_count:    views_sum.to_i,
      total_likes_count:    final_total_likes,
      total_comments_count: comments_sum.to_i,
      total_shares_count:   shares_sum.to_i,
      total_posts_count:    final_total_posts,
      snapshot_at:          snapshot_at || Time.current
    }

    record = AccountStat.find_or_initialize_by(account_id: account_id, stat_date: stat_date)
    record.assign_attributes(attrs)
    record.save!
    record
  end

  # === ransack（管理后台搜索） ===
  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      account_id
      stat_date
      followers_count
      total_views_count
      total_likes_count
      total_comments_count
      total_shares_count
      total_posts_count
      snapshot_at
      created_at
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account"]
  end
end
