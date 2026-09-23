# 抓取所有发文的详细数据
# 每日定期获取绑定正常账号（非Facebook），按单个账号依次推送到运营机器采集
#
# 调度模型：
#   - 查询所有状态为"正常"且非Facebook的账号（包含特殊账号）
#   - 仅处理绑定了浏览器且设置了machine_ip的账号
#   - 按浏览器分组，多个 worker 并行下发采集指令；并发/占用已交给机器端
#     （async 模式下机器端自己排队 + profile 锁 + 完成后回传 release）
#   - 依次调用 Util.fetch_account_post_data 推送单个账号采集指令
class PostDatas

  RETRY_COUNT = 2
  RETRY_DELAY = 20
  REQUEST_INTERVAL = 2
  ACCOUNT_INTERVAL = 15  # 单个账号之间的间隔（秒）
  STALE_ALERT_THRESHOLD = 10  # 未更新账号超过此数量则发送钉钉告警

  # 运营机器发文数据采集服务固定端口
  FETCH_PORT = 8080

  # 独立调试日志：专门记录 worker 池与占用决策（占用成功/失败原因/机器活跃数/补位），
  # 便于排查「流程是否正确、每机器≤4、连接池限制」等问题。写入 log/postdatas_debug.log。
  def self.dlog
    @dlog ||= begin
      l = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'postdatas_debug.log'))
      l.formatter = proc { |_severity, time, _progname, msg| "#{time.strftime('%Y-%m-%d %H:%M:%S')} #{msg}\n" }
      l
    end
  end

  # 采集入口
  # @param only_uncollected [Boolean] true 时只采集「今日还没采集过数据」的账号（跳过已更新的），
  #         false 时全量采集（今日未更新的排前面优先）。默认 false。
  # @param per_machine [Integer, nil] 每台机器每轮最多采集的账号数（按 id 升序取前 N 个）。
  #         传 nil 不限额。用于「凌晨分批采集」，每轮每机器取固定数量、自然轮转。
  # @param cooldown_hours [Integer, nil] 退避窗口（小时）：跳过「最近这么长时间内尝试过采集」的账号，
  #         避免出错账号（浏览器打不开/页面打不开，数据不回传）每轮都被选中占满配额、饿死正常账号。
  #         传 nil 不退避。仅 when only_uncollected 时生效。
  # @param machine_ips [Array<String>, nil] 只采集指定机器（machine_ip）的账号；nil 采集全部机器。
  def self.fetch(only_uncollected: false, per_machine: nil, cooldown_hours: nil, machine_ips: nil)
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'postdatas_fetch.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    special_account_ids = [213, 241, 253, 234, 233, 232, 231]

    # 1. 查询所有状态为"正常"且非Facebook的账号，必须绑定浏览器
    accounts = Account
                 .where(status: Account.statuses['正常'])
                 .where.not(platform: Account.platforms['facebook'])
                 .where.not(browser_id: nil)
                 .includes(:browser)
                 .to_a

    # 加入特殊账号（去重）
    special_accounts = Account.where(id: special_account_ids)
                                .where.not(browser_id: nil)
                                .includes(:browser)
                                .to_a
    accounts = (accounts + special_accounts).uniq { |a| a.id }

    # 2. 过滤掉未设置machine_ip的浏览器；指定 machine_ips 时只保留这些机器
    accounts = accounts.select do |a|
      a.browser.present? && a.browser.machine_ip.present? &&
        (machine_ips.nil? || machine_ips.include?(a.browser.machine_ip))
    end

    # 3. 计算「今天已更新」的账号：今天 post_stats 有更新 或 account_stat 有今日快照 视为「已更新」。
    today_start = Date.today.beginning_of_day
    today_end   = Date.today.end_of_day
    account_ids = accounts.map(&:id)

    updated_post_ids = PostStat.where(account_id: account_ids)
                               .where('data_updated_at >= ? AND data_updated_at <= ?', today_start, today_end)
                               .distinct.pluck(:account_id)
    updated_stat_ids = AccountStat.where(account_id: account_ids)
                                  .where(stat_date: Date.today)
                                  .distinct.pluck(:account_id)
    updated_ids = (updated_post_ids + updated_stat_ids).uniq

    if only_uncollected
      # 只采集今日未更新的账号：跳过今天已经采过的
      accounts.select! { |a| !updated_ids.include?(a.id) }
    else
      # 全量采集：今日未更新的排前面优先采集，已更新的排后面
      accounts.sort_by! { |a| updated_ids.include?(a.id) ? 1 : 0 }
    end

    # 退避：跳过「最近 cooldown_hours 小时内尝试过采集」的账号。
    # 出错账号（指纹浏览器打不开等）数据不回传、永远「未获取」，若不加退避会每轮都被选中
    # 占满前 per_machine 个配额，正常账号饿死。退避让它们歇几轮，正常账号才有机会轮转。
    if only_uncollected && cooldown_hours && cooldown_hours.to_i > 0
      cooldown_before = cooldown_hours.to_i.hours.ago
      accounts.select! { |a| a.last_fetch_attempted_at.nil? || a.last_fetch_attempted_at <= cooldown_before }
      Rails.logger.info "[PostDatas] 退避 #{cooldown_hours} 小时，跳过最近尝试过采集的账号，剩余候选 #{accounts.size} 个"
    end

    # 每台机器每轮限额：按 machine_ip 分组，每台机器按 id 升序取前 per_machine 个。
    # 采完的账号下轮因数据回传变「已更新」被排除，自然轮转到下一批，无需额外游标。
    if per_machine && per_machine.to_i > 0
      accounts = accounts.group_by { |a| a.browser.machine_ip }
                         .flat_map { |_ip, list| list.sort_by(&:id).first(per_machine.to_i) }
      Rails.logger.info "[PostDatas] 每台机器限额 #{per_machine.to_i} 个，本轮实际采集 #{accounts.size} 个账号"
    end

    total = accounts.size
    not_updated = accounts.count { |a| !updated_ids.include?(a.id) }
    Rails.logger.info "[PostDatas] 共筛选出 #{total} 个待采集账号（非Facebook、正常状态、绑定浏览器且有IP）"
    if only_uncollected
      Rails.logger.info "[PostDatas] 仅采集今日未更新的 #{total} 个账号"
    else
      Rails.logger.info "[PostDatas] 排序：今天未更新 #{not_updated} 个排前面优先采集，已更新 #{total - not_updated} 个排后面"
    end

    return { success_count: 0, fail_count: 0, total: 0, failed_items: [] } if accounts.empty?

    # 3. 按浏览器分组：一个分组 = 一个指纹浏览器下的所有账号。
    #    组内顺序执行（同一浏览器一次只能开一个），组间由 worker 并行下发；
    #    并发/占用由机器端统一把关（单机额度 + profile 串行锁 + 释放占用）。
    groups = accounts.group_by(&:browser_id).values.sort_by { |g| g.first.browser_id || 0 }
    machine_count = accounts.map { |a| a.browser.machine_ip }.uniq.size
    browser_names = groups.map { |g| "#{g.first.browser.profile_name}(#{g.size}个)" }
    Rails.logger.info "[PostDatas] 待采集浏览器 #{groups.size} 个（机器 #{machine_count} 台）: #{browser_names.join('、')}"

    # 4. worker 池并行下发采集指令：并发/占用已交给机器端（async 模式），
    #    worker 只负责并行「下发指令」，仅受数据库连接池大小限制。
    db_pool_size = ActiveRecord::Base.connection_pool.size
    pool_size = [groups.size, db_pool_size].min
    pool_size = 1 if pool_size <= 0

    dlog.info "[fetch] 账号=#{total} 机器=#{machine_count} 浏览器=#{groups.size} 连接池=#{db_pool_size}"
    dlog.info "[fetch] pool_size=min(浏览器=#{groups.size}, 连接池=#{db_pool_size})=#{pool_size}"

    mutex     = Mutex.new
    queue     = groups.dup          # 待处理浏览器分组（忙的会放回队尾）
    remaining = groups.size         # 尚未完成的分组数
    stats     = { success: 0, fail: 0, failed_items: [] }
    worker_id = 0

    # 释放主线程占用的连接，让 worker 线程能拿满整个连接池
    ActiveRecord::Base.connection_pool.release_connection

    workers = Array.new(pool_size) do
      wid = mutex.synchronize { worker_id += 1 }
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          loop do
            group = mutex.synchronize { queue.shift }
            unless group
              break if mutex.synchronize { remaining <= 0 }
              sleep(10)
              next
            end

            if fetch_browser_group(group, wid, mutex, stats) == :busy
              mutex.synchronize { queue << group }
              sleep(10)
            else
              mutex.synchronize { remaining -= 1 }
            end
          end
        end
      end
    end
    workers.each(&:join)

    success_count = stats[:success]
    fail_count    = stats[:fail]
    failed_items  = stats[:failed_items]

    dlog.info "[fetch] 完成 成功账号=#{success_count} 失败账号=#{fail_count} 总计账号=#{total}"

    Rails.logger.info "[PostDatas] 采集完成: 成功 #{success_count} 个, 失败 #{fail_count} 个, 总计 #{total} 个"
    if failed_items.any?
      Rails.logger.error "[PostDatas] 失败详情:"
      failed_items.each do |f|
        Rails.logger.error "[PostDatas]   - 账号 #{f[:account_name]}(ID=#{f[:account_id]}), 浏览器=#{f[:browser_name]}, IP=#{f[:machine_ip]}, 原因: #{f[:error]}"
      end
    end

    # 5. 采集完成后检查未更新数据的账号数量，超过阈值则发送钉钉告警
    #    只在全量采集时执行；「只补采未更新」模式下跳过（本来就是只采未更新的，无需再检查+重试）
    check_stale_accounts_and_alert(total, success_count, fail_count) unless only_uncollected

    { success_count: success_count, fail_count: fail_count, total: total, failed_items: failed_items }
  rescue => e
    Rails.logger.error "[PostDatas] 执行异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    { success_count: 0, fail_count: 0, total: 0, failed_items: [], error: e.message }
  end

  # 采集今日还没采集过数据的账号（只补采未更新的，跳过今天已经采过的）
  # 判定「今日已更新」：post_stats 今天有 data_updated_at，或 account_stat 有今日 stat_date。
  # 复用 fetch 的完整流程（筛选 → 过滤已更新 → 按浏览器分组 → worker 池并行下发），
  # 只是把「全量排序」换成「只保留未更新」。
  def self.fetch_uncollected_today
    fetch(only_uncollected: true)
  end

  # 每台机器每轮采集 N 个「今日未获取」的账号（用于凌晨分批采集，避免一次性堆积 + 中断自愈）。
  # 按 machine_ip 分组，每台机器按 id 升序取前 per_machine 个，采完的账号下轮变「已更新」被排除。
  # @param clear_pending [Boolean] 下发前是否先清掉机器端「排队中/执行中」的采集任务（fetch），
  #        避免上一轮未完成的任务与本轮重叠、堆积。默认 true。
  # @param cooldown_hours [Integer] 退避窗口（小时）：跳过「最近这么长时间内尝试过采集」的账号，
  #        避免出错账号（浏览器打不开等）每轮占满配额饿死正常账号。默认 3 小时。
  def self.fetch_uncollected_by_machine(per_machine: 42, clear_pending: true, cooldown_hours: 5)
    clear_pending_fetch_tasks if clear_pending
    fetch(only_uncollected: true, per_machine: per_machine, cooldown_hours: cooldown_hours)
  end

  # 清掉运营机器上「排队中(queued)/执行中(running)」的采集任务（type=fetch），
  # 用于每轮分批采集下发前，把上一轮还没跑完的采集任务停掉，避免重叠与堆积。
  # 被清掉的 running 任务会中断（数据未回传 → 账号仍「未获取」→ 下一轮重采，多花一轮但能补齐）。
  # @param machine_ips [Array<String>, nil] 要清理的机器 IP；nil 时清理全部配置了 machine_ip 的机器。
  # @return [Integer] 清除的任务总数
  def self.clear_pending_fetch_tasks(machine_ips = nil)
    machine_ips ||= Browser.where.not(machine_ip: [nil, ""]).distinct.pluck(:machine_ip)
    cleared = 0
    machine_ips.each do |ip|
      url = "https://#{ip}/tasks/clear?type=fetch&status=queued,running"
      resp = RemoteApiClient.post(url, {}, read_timeout: 30)
      count = (JSON.parse(resp.body.to_s)['count'] rescue 0).to_i
      cleared += count
      Rails.logger.info "[PostDatas] #{ip} 清理采集队列（queued/running）：清除 #{count} 个"
    rescue => e
      Rails.logger.warn "[PostDatas] #{ip} 清理采集队列失败：#{e.message}"
    end
    cleared
  end

  # 采集一个浏览器分组（该浏览器下的所有账号）：组内顺序执行。
  # 并发/占用已交给机器端（async 模式下机器端自己排队 + profile 锁），不再前置占用控制。
  # @return [Symbol] :done（已执行）
  def self.fetch_browser_group(group, worker_idx, mutex, stats)
    browser = group.first.browser
    label = "[worker#{worker_idx}]"

    dlog.info "#{label} START browser=#{browser.profile_name} ip=#{browser.machine_ip} accounts=#{group.size}"

    Rails.logger.info "[PostDatas] #{label} 开始采集浏览器 #{browser.profile_name}（#{group.size} 个账号，IP=#{browser.machine_ip}）"

    group.each_with_index do |account, index|
      begin
        Rails.logger.info "[PostDatas] #{label} [#{index + 1}/#{group.size}] 开始采集账号 #{account.account_name}(ID=#{account.id}, 平台=#{account.platform}, 浏览器=#{browser.profile_name}, IP=#{browser.machine_ip})"

        result = Util.fetch_account_post_data(account_id: account.id)

        if result[:success]
          mutex.synchronize { stats[:success] += 1 }
          Rails.logger.info "[PostDatas] #{label} [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}) 采集指令推送成功"
        else
          fail_info = {
            account_id: account.id,
            account_name: account.account_name,
            browser_name: browser.profile_name,
            machine_ip: browser.machine_ip,
            error: result[:message]
          }
          mutex.synchronize { stats[:fail] += 1; stats[:failed_items] << fail_info }
          Rails.logger.error "[PostDatas] #{label} [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}) 推送失败: #{result[:message]}"
        end
      rescue => e
        fail_info = {
          account_id: account.id,
          account_name: account.account_name,
          browser_name: browser&.profile_name,
          machine_ip: browser&.machine_ip,
          error: "异常: #{e.message}"
        }
        mutex.synchronize { stats[:fail] += 1; stats[:failed_items] << fail_info }
        Rails.logger.error "[PostDatas] #{label} [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}) 执行异常: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
      end

      # 组内最后一个账号不 sleep
      if index < group.size - 1
        Rails.logger.info "[PostDatas] #{label} 等待 #{ACCOUNT_INTERVAL} 秒后继续下一个账号..."
        sleep(ACCOUNT_INTERVAL)
      end
    end

    dlog.info "#{label} GROUP_DONE browser=#{browser.profile_name} accounts=#{group.size}"

    :done
  end

  # 检查未更新数据的账号，超过阈值发送钉钉告警
  def self.check_stale_accounts_and_alert(total_fetched, success_count, fail_count)
    begin
      stale_info = Util.get_stale_accounts
      post_stale_count = stale_info[:post_stats_stale]&.size || 0
      stat_stale_count = stale_info[:stat_stale]&.size || 0
      total_stale = stale_info[:total] || 0
      all_stale_ids = stale_info[:all_stale] || []

      Rails.logger.info "[PostDatas] 采集后数据更新检查 - 纳入统计账号: #{total_stale}, " \
                        "发文数据未更新: #{post_stale_count} 个, " \
                        "账号快照未更新: #{stat_stale_count} 个, " \
                        "合计未更新(all_stale): #{all_stale_ids.size} 个"

      # all_stale 超过阈值时，对这些账号重试一次采集推送
      retry_result = nil
      if all_stale_ids.size > STALE_ALERT_THRESHOLD
        Rails.logger.warn "[PostDatas] 合计未更新账号 #{all_stale_ids.size} 个超过阈值 #{STALE_ALERT_THRESHOLD}，开始重试采集"
        retry_result = retry_fetch_for_stale_accounts(all_stale_ids)
      end

      alerts = []
      if post_stale_count > STALE_ALERT_THRESHOLD
        alerts << "发文数据(post_stats)未更新账号过多: #{post_stale_count} 个（阈值: #{STALE_ALERT_THRESHOLD}）"
      end
      if stat_stale_count > STALE_ALERT_THRESHOLD
        alerts << "账号数据(account_stat)未更新账号过多: #{stat_stale_count} 个（阈值: #{STALE_ALERT_THRESHOLD}）"
      end

      if alerts.any?
        Rails.logger.warn "[PostDatas] 检测到数据异常: #{alerts.join('; ')}"
      else
        Rails.logger.info "[PostDatas] 未更新账号数量在正常范围内（post_stats=#{post_stale_count}, account_stat=#{stat_stale_count}, 阈值=#{STALE_ALERT_THRESHOLD}）"
      end
    rescue => e
      Rails.logger.error "[PostDatas] 检查stale账号或发送告警时异常: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    end
  end

  # 对未更新数据的账号重试一次采集推送
  # all_stale 超过阈值时由 check_stale_accounts_and_alert 触发。
  # 与主流程一致：按浏览器分组，直接下发采集指令（async 模式，并发/占用由机器端把关）。
  # @param stale_account_ids [Array<Integer>] 未更新数据的账号ID列表
  # @return [Hash] { total: Integer, success_count: Integer, fail_count: Integer }
  def self.retry_fetch_for_stale_accounts(stale_account_ids)
    return { total: 0, success_count: 0, fail_count: 0 } if stale_account_ids.blank?

    accounts = Account.where(id: stale_account_ids)
                      .where.not(browser_id: nil)
                      .includes(:browser)
                      .to_a
                      .select { |a| a.browser.present? && a.browser.machine_ip.present? }

    if accounts.empty?
      Rails.logger.warn "[PostDatas] 重试：未找到有效的未更新账号（传入 #{stale_account_ids.size} 个ID），跳过重试"
      return { total: 0, success_count: 0, fail_count: 0 }
    end

    groups = accounts.group_by(&:browser_id).values.sort_by { |g| g.first.browser_id || 0 }
    total = accounts.size

    Rails.logger.info "[PostDatas] 重试采集开始，共 #{total} 个账号（#{groups.size} 个浏览器）"

    success_count = 0
    fail_count = 0

    groups.each do |group|
      browser = group.first.browser

      dlog.info "[retry] START browser=#{browser.profile_name} ip=#{browser.machine_ip} accounts=#{group.size}"

      # 并发/占用已交给机器端（async 模式），直接下发采集指令
      group.each_with_index do |account, index|
        begin
          Rails.logger.info "[PostDatas] 重试 [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}, 平台=#{account.platform}, 浏览器=#{browser.profile_name})"
          result = Util.fetch_account_post_data(account_id: account.id)

          if result[:success]
            success_count += 1
            Rails.logger.info "[PostDatas] 重试 [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}) 推送成功"
          else
            fail_count += 1
            Rails.logger.error "[PostDatas] 重试 [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}) 推送失败: #{result[:message]}"
          end
        rescue => e
          fail_count += 1
          Rails.logger.error "[PostDatas] 重试 [#{index + 1}/#{group.size}] 账号 #{account.account_name}(##{account.id}) 异常: #{e.message}"
        end

        # 组内最后一个账号不需要sleep
        if index < group.size - 1
          sleep(ACCOUNT_INTERVAL)
        end
      end
    end

    Rails.logger.info "[PostDatas] 重试采集完成: 成功 #{success_count} 个, 失败 #{fail_count} 个, 总计 #{total} 个"
    { total: total, success_count: success_count, fail_count: fail_count }
  end

  # 按浏览器"混开"排序（发牌算法）
  # 将账号按browser_id分组，然后轮流从每个浏览器队列中取账号，尽量避免同一浏览器连续出现
  # @param accounts [Array<Account>] 账号列表
  # @return [Array<Account>] 混排后的账号列表
  def self.shuffle_accounts_by_browser(accounts)
    # 按browser_id分组
    grouped = accounts.group_by { |a| a.browser_id }

    # 每个组转成队列（数组），按浏览器ID排序保证确定性
    queues = grouped.keys.sort.map { |browser_id| grouped[browser_id].dup }

    result = []
    # 发牌：轮流从每个队列头部取一个账号
    until queues.empty?
      queues.each do |queue|
        result << queue.shift unless queue.empty?
      end
      # 移除空队列
      queues.reject!(&:empty?)
    end

    result
  end

  def self.push_to_external_with_retry(browser_data, endpoint)
    response = nil
    RETRY_COUNT.times do |attempt|
      response = push_to_external(browser_data, endpoint)
      return response if response[:success]

      if attempt < RETRY_COUNT - 1
        Rails.logger.warn "[PostDatas] 浏览器 #{browser_data[:profile_name]} 第 #{attempt + 1} 次尝试失败，#{RETRY_DELAY}秒后重试..."
        sleep(RETRY_DELAY)
      end
    end
    response
  end

  def self.push_to_external(browser_data, endpoint)
    response = RemoteApiClient.post(endpoint, browser_data, open_timeout: 300, read_timeout: 600)
    body = response.body

    if response.code == '200'
      { success: true, response: body }
    else
      { success: false, error: "HTTP #{response.code}: #{body}" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  # 解析运营机器返回体，将 posts 数组落库到 post_stats，
  # 然后基于 post_stats 聚合 + API返回的 total_followers/total_posts 生成 account_stat 日快照
  #
  # 返回体示例：
  #   {
  #     "type": "success",
  #     "profile_id": "2e1e7...",
  #     "results": [
  #       {
  #         "account_id": 2,
  #         "platform": "youtube",
  #         "total_followers": 1234,
  #         "total_posts": 56,
  #         "posts": [
  #           { "url": "...", "title": "...", "post_date": "2025-08-01",
  #             "likes_count": 100, "views_count": 2000, "comments_count": 10, "shares_count": 5 }
  #         ]
  #       }
  #     ]
  #   }
  #
  # 字段策略：
  # - total_followers：所有平台均使用API返回值
  # - total_posts：仅 YouTube/Instagram 使用API返回值，其他平台由 post_stats COUNT(*) 聚合
  # - posts 数组按 url upsert（已存在则更新计数，不存在则新建）
  # - total_likes/total_views/total_comments/total_shares：始终从 post_stats 聚合

  # 批量更新账号统计数据（公开接口，供外部API直接调用）
  # 仅更新粉丝数和发帖数，发文数据通过原接口（post_stats接口）录入
  # 总浏览/总点赞/总评论/总分享始终从 post_stats 表现有数据聚合计算
  #
  # @param results [Array<Hash>] 账号数据数组，每个元素格式：
  #   {
  #     account_id: Integer,        # 账号ID（必填）
  #     total_followers: Integer,   # 粉丝数（必填，所有平台均使用此值）
  #     total_posts: Integer        # 总发帖量（可选，YouTube/Instagram使用此值，其他平台从post_stats聚合）
  #   }
  # @return [Hash] { success: [account_ids], failed: [{account_id, error}] }
  def self.update_account_stats!(results)
    return { success: [], failed: [] } if results.blank? || !results.is_a?(Array)

    success_ids = []
    failed_items = []

    Rails.logger.info "[PostDatas] update_account_stats! 开始处理，共 #{results.size} 个账号"

    results.each do |item|
      raw_account_id = dig_value(item, :account_id, 'account_id')
      account_id = raw_account_id.to_i

      unless account_id > 0
        failed_items << { account_id: raw_account_id, error: "account_id 无效" }
        next
      end

      total_followers = dig_value(item, :total_followers, 'total_followers')
      total_posts     = dig_value(item, :total_posts, 'total_posts')
      Rails.logger.info "[PostDatas] update_account_stats! 处理账号 #{account_id}: total_followers=#{total_followers.inspect}, total_posts=#{total_posts.inspect}"

      begin
        # 直接基于现有 post_stats 数据生成当日快照
        # 总浏览/总点赞/总评论/总分享从post_stats聚合，不处理发文明细
        AccountStat.upsert_from_post_stats!(
          account_id,
          Date.today,
          followers_count: total_followers,
          total_posts:     total_posts,
          snapshot_at:     Time.current
        )
        success_ids << account_id
        Rails.logger.info "[PostDatas] update_account_stats! 账号 #{account_id} 更新成功 (followers=#{total_followers}, total_posts=#{total_posts})"
      rescue => e
        failed_items << { account_id: account_id, error: e.message }
        Rails.logger.error "[PostDatas] update_account_stats! 账号 #{account_id} 更新失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end

    Rails.logger.info "[PostDatas] update_account_stats! 处理完成: 成功=#{success_ids.size}, 失败=#{failed_items.size}"
    { success: success_ids, failed: failed_items }
  end

  # 从采集接口返回体中提取数据并落库（内部方法，供 fetch 和 util 调用）
  #
  # response_body 结构示例：
  #   { type: "success", profile_id: "...", results: [ { account_id, platform, posts: [...], total_followers, total_posts, ... } ] }
  #
  # 字段策略：
  # - total_followers：所有平台均使用API返回值
  # - total_posts：仅 YouTube/Instagram 使用API返回值，其他平台由 post_stats COUNT(*) 聚合
  # - posts 数组按 url upsert（已存在则更新计数，不存在则新建）
  # - total_likes/total_views/total_comments/total_shares：始终从 post_stats 聚合
  def self.snapshot_from_response!(response_body, browser_data)
    return unless response_body.present?

    Rails.logger.info "[PostDatas] snapshot_from_response! 开始处理，browser=#{browser_data[:profile_name]}, active_accounts数量=#{browser_data[:active_accounts]&.size}"

    parsed = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body.to_s)
    results = parsed.is_a?(Hash) ? parsed['results'] : nil

    if results.blank? || !results.is_a?(Array)
      Rails.logger.warn "[PostDatas] 返回体中无 results 数组或格式异常，跳过快照"
      return
    end

    # 本次推送涉及的 account_id 集合（白名单），统一转为 Integer 确保类型匹配
    pushed_account_ids = browser_data[:active_accounts].map { |a| a[:id].to_i }.compact.uniq
    Rails.logger.info "[PostDatas] 白名单 account_ids=#{pushed_account_ids.inspect}"

    results.each do |item|
      raw_account_id = dig_value(item, :account_id, 'account_id')
      account_id = raw_account_id.to_i

      unless account_id > 0
        Rails.logger.warn "[PostDatas] account_id无效(原始值=#{raw_account_id.inspect})，跳过"
        next
      end
      unless pushed_account_ids.include?(account_id)
        Rails.logger.warn "[PostDatas] 账号 #{account_id}(原始值=#{raw_account_id.inspect}) 不在本次推送白名单 #{pushed_account_ids.inspect} 中，跳过"
        next
      end

      total_followers = dig_value(item, :total_followers, 'total_followers')
      total_posts     = dig_value(item, :total_posts, 'total_posts')
      posts           = dig_value(item, :posts, 'posts') || []
      Rails.logger.info "[PostDatas] 处理账号 #{account_id}: total_followers=#{total_followers.inspect}, total_posts=#{total_posts.inspect}, posts数量=#{posts.is_a?(Array) ? posts.size : 'N/A'}"

      begin
        # 1. 先将 posts 数组落库到 post_stats（url 唯一，存在则更新，不存在则创建）
        saved_count = upsert_posts_for_account!(account_id, posts) if posts.is_a?(Array)

        # 2. 再生成 account_stat 日快照（此时 post_stats 已包含最新数据）
        AccountStat.upsert_from_post_stats!(
          account_id,
          Date.today,
          followers_count: total_followers,
          total_posts:     total_posts,
          snapshot_at:     Time.current
        )
        Rails.logger.info "[PostDatas] 账号 #{account_id} 快照更新成功! (posts_saved=#{saved_count || 0}, followers=#{total_followers}, total_posts=#{total_posts})"
      rescue => e
        Rails.logger.error "[PostDatas] 账号 #{account_id} 快照失败: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[PostDatas] 返回体 JSON 解析失败，跳过快照: #{e.message}"
  end

  # 从 Hash 中按优先级取多个可能的 key（兼容 symbol/string）
  # 使用 key? 判断 key 是否存在（而非 present?），确保 0、false、空字符串、空数组等合法值不被跳过
  # 仅当 key 不存在或值为 nil 时才继续尝试下一个 key
  def self.dig_value(hash, *keys)
    return nil unless hash.is_a?(Hash)
    keys.each do |k|
      if hash.key?(k)
        val = hash[k]
        return val unless val.nil?
      end
    end
    nil
  end

  # 将 posts 数组批量 upsert 到 post_stats
  # url 已存在则更新计数，不存在则新建
  # 兼容API返回的多种字段名（url/link, post_date/publish_time/date, likes_count/likes 等）
  # @return [Integer] 实际保存（新建+更新）的条数
  def self.upsert_posts_for_account!(account_id, posts)
    account = Account.find_by(id: account_id)
    return 0 unless account

    saved_count = 0
    posts.each do |post|
      next unless post.is_a?(Hash)

      # URL 字段：兼容 :url / :link / 'url' / 'link'，并清理反引号和空白
      raw_url = dig_value(post, :url, 'url', :link, 'link')
      next if raw_url.blank?
      url = raw_url.to_s.gsub('`', '').strip
      next if url.blank?

      # 发布日期：兼容 :post_date / :publish_time / :date / 'post_date' / 'publish_time' / 'date'
      raw_date = dig_value(post, :post_date, 'post_date', :publish_time, 'publish_time', :date, 'date', :publishTime, 'publishTime')
      post_date = begin
                    Date.parse(raw_date.to_s)
                  rescue
                    Date.today
                  end

      attrs = {
        account_id: account.id,
        post_date:  post_date,
        title:      dig_value(post, :title, 'title'),
        likes_count:     (dig_value(post, :likes_count, 'likes_count', :likes, 'likes', :like_count, 'like_count') || 0).to_i,
        views_count:     (dig_value(post, :views_count, 'views_count', :views, 'views', :view_count, 'view_count') || 0).to_i,
        comments_count:  (dig_value(post, :comments_count, 'comments_count', :comments, 'comments', :comment_count, 'comment_count') || 0).to_i,
        shares_count:    (dig_value(post, :shares_count, 'shares_count', :shares, 'shares', :share_count, 'share_count') || 0).to_i,
        data_updated_at: Time.current
      }

      existing = PostStat.find_by(url: url)
      if existing
        existing.update!(attrs)
      else
        PostStat.create!(attrs.merge(url: url))
      end
      saved_count += 1
    end
    saved_count
  end
end
