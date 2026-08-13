# 账号总量快照服务
# 触发时机：运营机器完成发文数据采集（PostDatas.fetch / 或 batch_create 接口）之后。
#
# 使用方式：
#   # 1) 给所有正常状态的账号批量生成今日快照（定时任务每天最后一步调用）
#   AccountStatsSnapshot.snapshot_all_today!
#
#   # 2) 针对单个账号立即生成今日快照（粉丝数已知时传入）
#   AccountStatsSnapshot.snapshot_account!(account, followers_count: 12345)
#
#   # 3) 根据采集端回调中的账号列表批量生成快照
#   AccountStatsSnapshot.snapshot_accounts!(account_ids, followers_map: { 123 => 9876 })
#
# 设计说明：
#   - 总浏览/点赞/评论/转发/发帖量 从已存在的 post_stats 表聚合得到，避免采集端重复上报。
#   - 粉丝数 followers_count 只能由采集端返回，因此参数可选传入；
#     如果采集端某次没有返回，则自动沿用该账号最近一次快照的粉丝数，保持累计值稳定。
#   - 使用 (account_id, stat_date) 唯一索引 + find_or_initialize_by，
#     同一天重复调用不会产生重复记录，而是用最新采集值覆盖。
class AccountStatsSnapshot
  # 批量生成今日快照：所有「正常」状态账号
  # 不传 total_followers / total_likes 时，AccountStat 内部会用最近一次快照的粉丝数 + post_stats 聚合的点赞数
  def self.snapshot_all_today!
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'account_stats_snapshot.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    accounts = Account.where(status: "正常").includes(:account_stats)
    Rails.logger.info "[AccountStatsSnapshot] 开始为 #{accounts.count} 个账号生成今日快照"

    success_count = 0
    fail_count    = 0

    accounts.find_each do |account|
      begin
        AccountStat.upsert_from_post_stats!(account.id, Date.today)
        success_count += 1
      rescue => e
        fail_count += 1
        Rails.logger.error "[AccountStatsSnapshot] 账号 #{account.id}(#{account.account_name}) 快照失败: #{e.message}"
      end
    end

    Rails.logger.info "[AccountStatsSnapshot] 快照完成: 成功 #{success_count} / 失败 #{fail_count}"
    { success_count: success_count, fail_count: fail_count, total: accounts.count }
  end

  # 给单个账号生成今日快照
  # @param account         [Account, Integer] Account 对象或 account_id
  # @param followers_count [Integer, nil]    采集端 total_followers
  # @param total_likes     [Integer, nil]    采集端 total_likes（仅 tiktok > 0）
  def self.snapshot_account!(account, followers_count: nil, total_likes: nil, snapshot_at: nil)
    account_id = account.is_a?(Account) ? account.id : account
    AccountStat.upsert_from_post_stats!(
      account_id,
      Date.today,
      followers_count: followers_count,
      total_likes:     total_likes,
      snapshot_at:     snapshot_at
    )
  end

  # 批量给指定账号集合生成今日快照
  # @param account_ids    [Array<Integer>]
  # @param stats_map     [Hash<Integer, Hash>] { account_id => { followers_count:, total_likes: } }
  def self.snapshot_accounts!(account_ids, stats_map: {}, snapshot_at: nil)
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'account_stats_snapshot.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    success_count = 0
    fail_count    = 0

    Array(account_ids).each do |account_id|
      begin
        stat = stats_map[account_id] || {}
        AccountStat.upsert_from_post_stats!(
          account_id,
          Date.today,
          followers_count: stat[:followers_count],
          total_likes:     stat[:total_likes],
          snapshot_at:     snapshot_at
        )
        success_count += 1
      rescue => e
        fail_count += 1
        Rails.logger.error "[AccountStatsSnapshot] 账号 #{account_id} 快照失败: #{e.message}"
      end
    end

    { success_count: success_count, fail_count: fail_count, total: account_ids.size }
  end
end
