# 外部采集系统适配器（骨架）。
#
# 数据流（异步）：
#   ① deploy 把「需外部采集」的账号提交到外部采集系统触发采集；
#   ② 延迟一段时间后 pull 拉取结果并落库。
#
# 账号标识用 external_user_id（各平台 user_id 或 username），不用主页链接。
# 接口地址/认证/响应字段待提供，先用 ENV 占位，字段映射对接外部系统后补齐。
#
# 落库路由：
#   - Account        → account_stat（粉丝/发帖快照）+ post_stats（发文明细）
#   - HostingAccount → hosting_account_stats（粉丝/发帖/聚合量）
class ExternalStatsFetcher
  DEPLOY_URL = ENV['EXTERNAL_FETCH_DEPLOY_URL']
  PULL_URL   = ENV['EXTERNAL_FETCH_PULL_URL']
  API_KEY    = ENV['EXTERNAL_FETCH_API_KEY']

  # 需要部署到外部采集系统的目标：
  # - Account：external_fetch_enabled=true 且 external_user_id 非空
  # - HostingAccount：external_user_id 非空（且账号 + 客户均 active）
  def self.deploy_targets
    accounts = Account
      .where(external_fetch_enabled: true)
      .where.not(external_user_id: [nil, ''])
      .map { |a| { kind: :account, id: a.id, platform: a.platform, user_id: a.external_user_id } }

    hosting = HostingAccount.publishable
      .where.not(external_user_id: [nil, ''])
      .map { |h| { kind: :hosting, id: h.id, platform: h.platform, user_id: h.external_user_id } }

    accounts + hosting
  end

  # 部署：提交账号到外部采集系统触发采集
  def self.deploy
    targets = deploy_targets
    return { total: 0, success: 0 } if targets.empty?

    payload = { api_key: API_KEY, accounts: targets }
    # TODO: 对接外部采集系统部署接口（POST DEPLOY_URL）
    # resp = RemoteApiClient.post(DEPLOY_URL, payload, read_timeout: 60)
    # ... 解析 resp，统计成功数
    { total: targets.size, success: targets.size }
  rescue => e
    Rails.logger.error "[ExternalStatsFetcher] deploy 失败: #{e.message}"
    { total: 0, success: 0, error: e.message }
  end

  # 拉取结果并落库
  def self.pull
    # TODO: 对接外部采集系统拉取接口（GET PULL_URL），返回部署账号的采集结果数组
    results = []  # 每项含 kind/id + followers/total_posts/total_views/.../posts
    results.each { |r| store_result(r) }

    { total: results.size }
  rescue => e
    Rails.logger.error "[ExternalStatsFetcher] pull 失败: #{e.message}"
    { total: 0, error: e.message }
  end

  # 单条结果落库（按 kind 路由）
  def self.store_result(result)
    case result[:kind] || result['kind']
    when :account, 'account'
      store_account_result(result[:id] || result['id'], result)
    when :hosting, 'hosting'
      store_hosting_result(result[:id] || result['id'], result)
    end
  end

  # Account 结果 → account_stat + post_stats（复用现有）
  def self.store_account_result(account_id, data)
    followers = data[:followers] || data['followers']
    total_posts = data[:total_posts] || data['total_posts']
    posts = data[:posts] || data['posts']

    PostDatas.upsert_posts_for_account!(account_id, posts) if posts.is_a?(Array) && posts.any?
    AccountStat.upsert_from_post_stats!(
      account_id,
      Date.today,
      followers_count: followers,
      total_posts: total_posts,
      snapshot_at: Time.current
    )
  end

  # HostingAccount 结果 → hosting_account_stats
  def self.store_hosting_result(hosting_account_id, data)
    stat = HostingAccountStat.find_or_initialize_by(hosting_account_id: hosting_account_id, stat_date: Date.today)
    stat.update!(
      followers_count: data[:followers] || data['followers'],
      total_posts:     data[:total_posts] || data['total_posts'],
      total_views:     data[:total_views] || data['total_views'],
      total_likes:     data[:total_likes] || data['total_likes'],
      total_comments:  data[:total_comments] || data['total_comments'],
      total_shares:    data[:total_shares] || data['total_shares'],
      snapshot_at:     Time.current
    )
  end
end
