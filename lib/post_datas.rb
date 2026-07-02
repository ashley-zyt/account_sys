# 抓取所有发文的详细数据
# 每日定期获取绑定正常账号的浏览器列表，推送到外部接口采集发文数据
class PostDatas

  SPECIAL_ACCOUNT_IDS = [213, 241, 253, 234, 233, 232, 231]

  def self.ensure_utf8(str)
    return str unless str.is_a?(String)
    str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  end

  def self.fetch
    SPECIAL_ACCOUNT_IDS = [213, 241, 253, 234, 233, 232, 231]

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
        profile_name: self.ensure_utf8(browser.profile_name),
        active_accounts: active_accounts.map do |acc|
          {
            id: acc.id,
            platform: self.ensure_utf8(acc.platform),
            source_url: self.ensure_utf8(acc.source_url)
          }
        end
      }
    end

    special_accounts = Account.where(id: SPECIAL_ACCOUNT_IDS).where.not(browser_id: nil)
    special_accounts.group_by(&:browser_id).each do |browser_id, accounts|
      browser = Browser.find_by(id: browser_id)
      next unless browser

      existing_item = data.find { |item| item[:id] == browser.id }
      if existing_item
        existing_item[:active_accounts] += accounts.map do |acc|
          {
            id: acc.id,
            platform: self.ensure_utf8(acc.platform),
            source_url: self.ensure_utf8(acc.source_url)
          }
        end
        existing_item[:active_accounts].uniq! { |acc| acc[:id] }
      else
        data << {
          id: browser.id,
          profile_name: self.ensure_utf8(browser.profile_name),
          active_accounts: accounts.map do |acc|
            {
              id: acc.id,
              platform: self.ensure_utf8(acc.platform),
              source_url: self.ensure_utf8(acc.source_url)
            }
          end
        }
      end
    end

    Rails.logger.info "[PostDatas] 共 #{data.size} 个浏览器需要采集发文数据（包含 #{special_accounts.size} 个特殊账号）"

    success_count = 0
    fail_count = 0

    data.each do |browser_data|
      response = push_to_external(browser_data)
      if response[:success]
        success_count += 1
        Rails.logger.info "[PostDatas] 浏览器 #{browser_data[:profile_name]} 推送成功"
      else
        fail_count += 1
        Rails.logger.error "[PostDatas] 浏览器 #{browser_data[:profile_name]} 推送失败: #{self.ensure_utf8(response[:error])}"
      end
    end

    Rails.logger.info "[PostDatas] 采集完成: 成功 #{success_count} 个, 失败 #{fail_count} 个"
    { success_count: success_count, fail_count: fail_count, total: data.size }
  rescue => e
    Rails.logger.error "[PostDatas] 执行异常: #{self.ensure_utf8(e.message)}"
    { success_count: 0, fail_count: 0, total: 0, error: e.message }
  end

  # 推送单个浏览器数据到外部接口
  def self.push_to_external(browser_data)
    uri = URI.parse("http://174.139.46.117:8080/accounts/fetch_posts")
    http = Net::HTTP.new(uri.host, uri.port)
    http.read_timeout = 300
    http.open_timeout = 300

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request.body = browser_data.to_json

    response = http.request(request)
    body = self.ensure_utf8(response.body)

    if response.code == '200'
      { success: true, response: body }
    else
      { success: false, error: "HTTP #{response.code}: #{body}" }
    end
  rescue => e
    { success: false, error: self.ensure_utf8(e.message) }
  end
end
