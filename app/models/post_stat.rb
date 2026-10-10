# == Schema Information
#
# Table name: post_stats
#
#  id                            :bigint           not null, primary key
#  comments_count(评论数量)      :integer          default(0)
#  data_updated_at(数据更新时间) :datetime
#  likes_count(点赞数量)         :integer          default(0)
#  post_date(发文日期)           :date             not null
#  shares_count(转发数量)        :integer          default(0)
#  title(发文标题)               :string(255)
#  url(发文链接)                 :string(255)
#  views_count(浏览数量)         :integer          default(0)
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id(账号ID)            :bigint           not null
#
# Indexes
#
#  index_post_stats_on_account_id  (account_id)
#  index_post_stats_on_post_date   (post_date)
#  index_post_stats_on_url         (url) UNIQUE
#

class PostStat < ApplicationRecord
	belongs_to :account

	validates :account_id, presence: true
	validates :post_date, presence: true
	validates :url, presence: true, uniqueness: true
	validates :likes_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
	validates :shares_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
	validates :comments_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
	validates :views_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_date_range, ->(start_date, end_date) { where(post_date: start_date..end_date) }
  scope :order_by_date, -> { order(post_date: :desc) }
  scope :updated_today, -> { where(data_updated_at: Time.zone.today.beginning_of_day..Time.zone.today.end_of_day) }

  # 统计每个账号今日更新的记录个数
  def self.today_updates_with_account_info
    today_start = Time.zone.today.beginning_of_day
    today_end = Time.zone.today.end_of_day

    PostStat
      .joins(:account)
      .where(data_updated_at: today_start..today_end).where(accounts: { work_type: "人工运营" })
      .group('post_stats.account_id, accounts.platform')
      .select('post_stats.account_id, accounts.platform, COUNT(*) as update_count')
      .map do |stat|
        {
          account_id: stat.account_id,
          platform: stat.platform,
          update_count: stat.update_count.to_i
        }
      end
  end


  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      account_id
      post_date
      title
      url
      likes_count
      shares_count
      comments_count
      views_count
      data_updated_at
      created_at
      updated_at
      publish_channel
    ]
  end

  # 实际发布渠道：从该账号「发文当天」最近一次成功发布日志里取渠道（task_logs.publish_channel）。
  # 用于 post_stats 按实际渠道筛选（PostStat 本身不存渠道，这里通过子查询关联 task_logs）。
  ransacker :publish_channel, formatter: proc { |v| v.to_i } do
    Arel.sql(
      "(SELECT tl.publish_channel FROM task_logs tl " \
      "WHERE tl.account_id = post_stats.account_id " \
      "AND tl.status = 'success' " \
      "AND tl.publish_channel IS NOT NULL " \
      "AND DATE(tl.run_at) = post_stats.post_date " \
      "ORDER BY tl.id DESC LIMIT 1)"
    )
  end

  def self.ransackable_associations(auth_object = nil)
    ["account"]
  end
end
