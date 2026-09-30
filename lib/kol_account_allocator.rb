# KOL 内部发信账号调度器
#
# 分配策略：
#   1. 账号状态=正常 且 平台一致
#   2. 必须有发文记录（一条发文都没有则略过），平均浏览量只作优先级排序、不再作为门槛
#   3. 按平均浏览量从高到低选择
#   4. 单个账号每日最多尝试发私信 5 次（成功+失败都算），发满当天不再分配、次日继续
#   5. 风控/发送失败的账号休眠一段时间，期间不参与分配
class KolAccountAllocator
  MAX_CONTACTS_PER_DAY = 5  # 默认值，可被 config/kol_scheduler.yml 的 max_contacts_per_day 覆盖
  SLEEP_HOURS = 24
  CONFIG_PATH = Rails.root.join('config/kol_scheduler.yml')
  # 当前已接通 twitter / tiktok / instagram / facebook
  SUPPORTED_PLATFORMS = %w[twitter tiktok instagram facebook].freeze
  # 无发文数据、无需按浏览量评分的平台（直接返回全部正常账号）
  SKIP_POST_SCORING_PLATFORMS = %w[facebook].freeze

  class << self
    # 读取调度配置（config/kol_scheduler.yml），文件不存在或字段缺失回退默认值
    def settings
      @settings ||= begin
        require 'yaml'
        File.exist?(CONFIG_PATH) ? (YAML.load_file(CONFIG_PATH) || {}) : {}
      end
    end

    # 单账号每日尝试发私信的上限（可后台配置，成功+失败都算）
    def max_contacts_per_day
      (settings['max_contacts_per_day'].presence || MAX_CONTACTS_PER_DAY).to_i
    end

    # 清除配置缓存（后台修改 yml 后调用，使新值立即生效）
    def reload_settings!
      @settings = nil
    end

    def supported_platform?(platform)
      SUPPORTED_PLATFORMS.include?(platform.to_s)
    end

    # 分配一个可用账号；无可用账号或平台未接通时返回 nil
    # @param channel [Symbol, String] 触达方式：:x_api（X 认证，默认）/ :browser（指纹浏览器）。
    #   x_api 时只选「X 授权成功」的账号（有可用 access_token）。
    # @param domain_id [Integer, nil] 目标领域 ID。传入时**只选领域相同的账号**（不同领域的直接跳过）。
    def allocate(platform, exclude_ids: [], channel: :x_api, domain_id: nil)
      return nil unless supported_platform?(platform)

      candidates = ordered_candidates(platform)

      # 领域硬过滤：账号 theme 所属领域（Theme.domain_id）必须 == 目标领域，不同领域的账号直接排除
      if domain_id.present?
        theme_domains = Theme.where(name: candidates.map(&:theme).compact.uniq).pluck(:name, :domain_id).to_h
        candidates = candidates.select { |a| theme_domains[a.theme] == domain_id }
      end

      candidates.each do |account|
        next if exclude_ids.include?(account.id)
        next if account.kol_sleeping?
        next if today_contact_count(account) >= max_contacts_per_day
        # X 认证方式：只选 X 授权成功的账号
        next if channel.to_s == 'x_api' && !account.x_credential&.authorized?
        # 指纹浏览器方式：只选绑定了浏览器（有 machine_ip）的账号
        next if channel.to_s != 'x_api' && account.browser&.machine_ip.blank?
        return account
      end
      nil
    end

    # 发送失败/风控后休眠内部账号
    def sleep_account(account, hours: SLEEP_HOURS)
      account.update!(kol_sleep_until: hours.hours.from_now)
    end

    # 判断是否「今日配额已耗尽」：所有支持平台的正常账号，今日尝试次数（成功+失败）都达到上限（或平台无账号）。
    # 配额耗尽时应等第二天自然日重置，而不是短时间重试空转。
    def self.quota_exhausted?
      SUPPORTED_PLATFORMS.all? do |platform|
        account_ids = Account.active.where(platform: platform).pluck(:id)
        next true if account_ids.empty?

        sent = KolMessage.where(
          account_id: account_ids,
          direction: KolMessage.directions[:outgoing],
          status: [KolMessage.statuses[:sent_success], KolMessage.statuses[:sent_failed]],
          created_at: Time.current.beginning_of_day..Time.current.end_of_day
        ).group(:account_id).count

        account_ids.all? { |id| sent[id].to_i >= max_contacts_per_day }
      end
    end

    private

    # 正常 + 同平台，按「近七条发文」的平均浏览量降序；
    # 一条发文都没有的账号直接略过（不参与分配）。
    def ordered_candidates(platform)
      account_ids = Account.active.where(platform: platform).pluck(:id)
      return [] if account_ids.empty?

      # 无发文数据的平台（如 facebook）跳过浏览量评分，直接返回全部正常账号，
      # 按「最久未使用」优先，兼顾账号轮询平衡
      if SKIP_POST_SCORING_PLATFORMS.include?(platform.to_s)
        return Account.where(id: account_ids).includes(:x_credential, :browser).order(:last_used_at, :id).to_a
      end

      # 按发文日期倒序拉取每个账号的浏览量，再逐个账号截取最近 7 条
      stats = PostStat.where(account_id: account_ids)
                      .order(account_id: :asc, post_date: :desc, id: :desc)
                      .pluck(:account_id, :views_count)

      by_account = Hash.new { |h, k| h[k] = [] }
      stats.each do |account_id, views_count|
        list = by_account[account_id]
        list << views_count.to_i if list.size < 7
      end

      scored = []
      by_account.each do |account_id, views|
        next if views.empty?          # 一条发文都没有：略过
        scored << [account_id, views.sum.to_f / views.size]
      end

      # 只按平均浏览量降序排序（作为优先级），不再以浏览量作为分配门槛
      scored.sort_by! { |_id, avg| -avg }
      ids = scored.map(&:first)
      accounts_by_id = Account.where(id: ids).includes(:x_credential, :browser).index_by(&:id)
      ids.map { |id| accounts_by_id[id] }.compact
    end

    # 单个账号今日「尝试发私信」的次数：成功 + 失败都算一次。
    # 失败同样占配额，避免失败账号（对方拒绝/权限问题）被反复分配无限重试。
    def today_contact_count(account)
      KolMessage.where(
        account_id: account.id,
        direction: KolMessage.directions[:outgoing],
        status: [KolMessage.statuses[:sent_success], KolMessage.statuses[:sent_failed]]
      ).where(created_at: Time.current.beginning_of_day..Time.current.end_of_day).count
    end
  end
end
