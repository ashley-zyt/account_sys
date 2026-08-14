# 抓取所有发文的详细数据
# 每日定期获取绑定正常账号的浏览器列表，推送到该浏览器所属运营机器采集发文数据
#
# 调度模型：
#   - 按浏览器所属运营机器 IP（browser.machine_ip）分组
#   - 每台机器一个 Thread 并行推送，互不影响
#   - 端点动态生成：http://<browser.machine_ip>:8080/accounts/fetch_posts（端口固定 8080）
#   - 一个浏览器只属于一台机器，其下所有账号（不论 work_type）统一推送到该机器
class PostDatas

  RETRY_COUNT = 2
  RETRY_DELAY = 20
  REQUEST_INTERVAL = 2

  # 运营机器发文数据采集服务固定端口
  FETCH_PORT = 8080

  def self.fetch
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'postdatas_fetch.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    special_account_ids = [213, 241, 253, 234, 233, 232, 231]

    browsers = Browser
                 .joins(:accounts)
                 .where(accounts: { status: Account.statuses['正常'] })
                 .where.not(accounts: { platform: Account.platforms['facebook'] })
                 .distinct
                 .order(created_at: :desc)
    data = browsers.map do |browser|
      active_accounts = browser.accounts
                          .where(status: Account.statuses['正常'])
                          .where.not(platform: Account.platforms['facebook'])
      {
        id: browser.id,
        profile_name: browser.profile_name,
        machine_ip: browser.machine_ip,
        active_accounts: active_accounts.map do |acc|
          {
            id: acc.id,
            platform: acc.platform,
            source_url: acc.source_url,
            work_type: acc.work_type
          }
        end
      }
    end

    special_accounts = Account.where(id: special_account_ids).where.not(browser_id: nil)
    special_accounts.group_by(&:browser_id).each do |browser_id, accounts|
      browser = Browser.find_by(id: browser_id)
      next unless browser

      existing_item = data.find { |item| item[:id] == browser.id }
      if existing_item
        existing_item[:active_accounts] += accounts.map do |acc|
          {
            id: acc.id,
            platform: acc.platform,
            source_url: acc.source_url,
            work_type: acc.work_type
          }
        end
        existing_item[:active_accounts].uniq! { |acc| acc[:id] }
      else
        data << {
          id: browser.id,
          profile_name: browser.profile_name,
          machine_ip: browser.machine_ip,
          active_accounts: accounts.map do |acc|
            {
              id: acc.id,
              platform: acc.platform,
              source_url: acc.source_url,
              work_type: acc.work_type
            }
          end
        }
      end
    end

    Rails.logger.info "[PostDatas] 共 #{data.size} 个浏览器需要采集发文数据（包含 #{special_accounts.size} 个特殊账号）"

    # 按运营机器 IP 分组：一个浏览器只属于一台机器，其下所有账号统一推送到该机器
    grouped_by_machine = data.group_by { |item| item[:machine_ip] }
    machine_ips = grouped_by_machine.keys.compact.reject(&:blank?).sort
    orphan_count = data.count { |item| item[:machine_ip].blank? }

    if orphan_count > 0
      Rails.logger.warn "[PostDatas] 有 #{orphan_count} 个浏览器未设置 machine_ip，本轮跳过，请在浏览器页面补全机器IP"
    end

    Rails.logger.info "[PostDatas] 发现 #{machine_ips.size} 台运营机器: #{machine_ips.join(', ')}"

    return { success_count: 0, fail_count: 0, total: data.size } if machine_ips.empty?

    # 每台机器并行推送其下所有浏览器
    success_count = 0
    fail_count = 0
    success_mutex = Mutex.new

    threads = machine_ips.map do |ip|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          browser_items = grouped_by_machine[ip]
          machine_success = 0
          machine_fail = 0

          browser_items.each_with_index do |browser_data, index|
            begin
              payload = {
                id: browser_data[:id],
                profile_name: browser_data[:profile_name],
                active_accounts: browser_data[:active_accounts]
              }
              endpoint = "http://#{ip}:#{FETCH_PORT}/accounts/fetch_posts"
              response = push_to_external_with_retry(payload, endpoint)

              if response[:success]
                machine_success += 1
                Rails.logger.info "[PostDatas] 机器 #{ip} 浏览器 #{browser_data[:profile_name]} 推送成功 (第 #{index + 1} 个, 目标: #{endpoint})"

                # 推送成功后解析返回体，提取每个账号的 total_followers / total_posts
                # 落库到 account_stat 表（当天日维度快照）
                snapshot_from_response!(response[:response], browser_data)
              else
                machine_fail += 1
                Rails.logger.error "[PostDatas] 机器 #{ip} 浏览器 #{browser_data[:profile_name]} 推送失败: #{response[:error]} (第 #{index + 1} 个, 目标: #{endpoint})"
              end
            rescue => e
              machine_fail += 1
              Rails.logger.error "[PostDatas] 机器 #{ip} 浏览器 #{browser_data[:profile_name]} 执行异常: #{e.message}"
            end

            sleep(REQUEST_INTERVAL) unless index == browser_items.size - 1
          end

          success_mutex.synchronize do
            success_count += machine_success
            fail_count += machine_fail
          end
        end
      end
    end
    threads.each(&:join)

    Rails.logger.info "[PostDatas] 采集完成: 成功 #{success_count} 个, 失败 #{fail_count} 个"
    { success_count: success_count, fail_count: fail_count, total: data.size }
  rescue => e
    Rails.logger.error "[PostDatas] 执行异常: #{e.message}"
    { success_count: 0, fail_count: 0, total: 0, error: e.message }
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
    uri = URI.parse(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 600
    http.open_timeout = 300

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request.body = browser_data.to_json.force_encoding('UTF-8')

    response = http.request(request)
    body = response.body

    if response.code == '200'
      { success: true, response: body }
    else
      { success: false, error: "HTTP #{response.code}: #{body}" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  # 解析运营机器返回体，提取每个账号的 total_followers / total_posts
  # 落库到 account_stat 当天日维度快照
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
  #         "total_posts": 56,           # 总发帖量（API返回）
  #         "posts": [...]
  #       }
  #     ]
  #   }
  #
  # 说明：
  # - 仅 results 中的 account_id 在本次推送列表里才会落库（避免误写其他账号）
  # - total_followers：所有平台均使用API返回值
  # - total_posts：仅 YouTube/Instagram 使用API返回值，其他平台由 upsert_from_post_stats! 内部从 post_stats COUNT(*) 聚合
  # - total_likes：不使用API返回值，由 upsert_from_post_stats! 内部从 post_stats 聚合计算
  # - total_views/total_comments/total_shares：均从 post_stats 聚合计算
  def self.snapshot_from_response!(response_body, browser_data)
    return unless response_body.present?

    parsed = response_body.is_a?(Hash) ? response_body : JSON.parse(response_body.to_s)
    results = parsed.is_a?(Hash) ? parsed['results'] : nil
    return if results.blank? || !results.is_a?(Array)

    # 本次推送涉及的 account_id 集合（白名单）
    pushed_account_ids = browser_data[:active_accounts].map { |a| a[:id] }.compact

    results.each do |item|
      account_id = item['account_id'] || item[:account_id]
      next unless account_id.present?
      next unless pushed_account_ids.include?(account_id)

      total_followers = item['total_followers'] || item[:total_followers]
      total_posts     = item['total_posts']     || item[:total_posts]

      begin
        AccountStat.upsert_from_post_stats!(
          account_id,
          Date.today,
          followers_count: total_followers,
          total_posts:     total_posts,
          snapshot_at:     Time.current
        )
        Rails.logger.info "[PostDatas] 账号 #{account_id} account_stat 快照已更新 (followers=#{total_followers}, total_posts=#{total_posts})"
      rescue => e
        Rails.logger.error "[PostDatas] 账号 #{account_id} account_stat 快照失败: #{e.message}"
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[PostDatas] 返回体 JSON 解析失败，跳过快照: #{e.message}"
  end
end
