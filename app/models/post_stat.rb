# == Schema Information
#
# Table name: post_stats
#
#  id                                                      :bigint           not null, primary key
#  comments_count(评论数量)                                :integer          default(0)
#  data_updated_at(数据更新时间)                           :datetime
#  likes_count(点赞数量)                                   :integer          default(0)
#  post_date(发文日期)                                     :date             not null
#  publish_channel(实际发布渠道 0浏览器 1postforme 2x_api 3postpeer) :integer
#  shares_count(转发数量)                                  :integer          default(0)
#  title(发文标题)                                         :text(65535)
#  url(发文链接)                                           :text(65535)
#  views_count(浏览数量)                                   :integer          default(0)
#  created_at                                              :datetime         not null
#  updated_at                                              :datetime         not null
#  account_id(账号ID)                                      :bigint           not null
#
# Indexes
#
#  index_post_stats_on_account_id       (account_id)
#  index_post_stats_on_post_date        (post_date)
#  index_post_stats_on_publish_channel  (publish_channel)
#  index_post_stats_on_url              (url) UNIQUE
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

  # 根据发文链接反查实际发布渠道（精确匹配）：
  # - postforme：postforme_posts.platform_url 精确匹配
  # - x_api：url 末尾 /status/<tweet_id> 匹配 x_posts.tweet_id
  # - 浏览器渠道暂无法按 url 反查（发布成功后未落库 url），匹配不到留空
  # @return [Integer, nil] 渠道值（1=postforme / 2=x_api），匹配不到返回 nil
  def self.resolve_publish_channel(url)
    clean = url.to_s.strip
    return nil if clean.blank?

    return Account.publish_channels['postforme'] if PostformePost.exists?(platform_url: clean)
    return Account.publish_channels['postpeer'] if PostpeerPost.exists?(platform_url: clean)

    if clean =~ %r{/status/(\d+)}
      tweet_id = $1
      return Account.publish_channels['x_api'] if XPost.exists?(tweet_id: tweet_id)
    end

    nil
  end

  # 按「账号 + 日期」反查发布渠道：查该账号当天最后一条成功发布的渠道。
  # 说明：url 精确反查不可靠（postforme 返回的 platform_url 与采集端回传的真实帖子 url
  # 格式不一致，如 tiktok 主页 vs 视频、instagram reel 无用户名、youtube watch vs shorts），
  # 改用「账号 + 发布日期 → 当天最后一条成功发布日志的渠道」。
  # @return [Integer, nil] 渠道值（0浏览器 1postforme 2x_api 3postpeer），查不到返回 nil
  def self.resolve_publish_channel_by_account_date(account_id, post_date)
    return nil if account_id.blank? || post_date.blank?

    # 放宽到 post_date 前后各 1 天：浏览器发布是异步的，task_log.run_at 是回调时间，
    # 与采集端读到的帖子 post_date 可能跨天错位（尤其凌晨/跨天发布、时区差异）。
    day_start = (post_date - 1.day).beginning_of_day
    day_end   = (post_date + 1.day).end_of_day

    # 按 run_at 与 post_date 的日期差升序取最接近的一条，避免误取到相邻日的发布
    raw = TaskLog.where(account_id: account_id)
                 .where.not(publish_channel: nil)
                 .where(status: TaskLog.statuses[:success])
                 .where(run_at: day_start..day_end)
                 .order(Arel.sql("ABS(DATEDIFF(run_at, '#{post_date}')) ASC"), :id)
                 .pick(:publish_channel)

    # pick 对 enum 字段返回字符串 key（如 "x_api"），而 post_stats.publish_channel 是整数列，
    # 这里转回整数值（0/1/2/3），避免把字符串写入整数列时被当成 0。
    return nil if raw.blank?
    TaskLog.publish_channels[raw] || raw
  end

  def self.ransackable_associations(auth_object = nil)
    ["account"]
  end
end
