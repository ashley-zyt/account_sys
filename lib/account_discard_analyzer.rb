# 弃用账号分析器
#
# 输入一批要弃用的账号 ID，打印：
#   1. 每个弃用账号对应的浏览器（profile_name）与代理
#   2. 每个涉及到的浏览器下，还有哪些「正常状态」的账号（平台 + 账号名）
#
# 用法：AccountDiscardAnalyzer.analyze([1, 2, 3])
class AccountDiscardAnalyzer
  class << self
    def analyze(account_ids)
      ids = Array(account_ids).map(&:to_i).reject(&:zero?)
      return puts("未提供账号 ID") if ids.empty?

      accounts = Account.where(id: ids).includes(:browser).order(:id)

      puts "\n===== 弃用账号清单（共 #{accounts.size} 个）====="
      puts "ID\t账号名\t平台\t状态\t浏览器\t代理"
      accounts.each do |a|
        b = a.browser
        puts [a.id, a.account_name, a.platform, a.status, b&.profile_name, proxy_text(b)].join("\t")
      end

      browser_ids = accounts.map(&:browser_id).compact.uniq
      puts "\n===== 涉及的浏览器（共 #{browser_ids.size} 个）====="

      browser_ids.each do |bid|
        b = Browser.find_by(id: bid)
        next if b.nil?

        active = b.accounts.where(status: Account.statuses["正常"]).order(:platform, :id)
        puts "\n浏览器：#{b.profile_name}  代理：#{proxy_text(b)}"
        puts "  该浏览器下正常状态账号（#{active.size} 个）："
        if active.any?
          active.each { |a| puts "    #{a.id}\t#{a.account_name}\t#{a.platform}" }
        else
          puts "    （无正常账号，浏览器可一并弃用）"
        end
      end

      nil
    end

    # 拼代理展示字符串：type://user:pass@host:port（无认证则 type://host:port）
    def proxy_text(browser)
      return '-' if browser.nil? || browser.proxy_host.blank?
      auth = browser.proxy_username.present? ? "#{browser.proxy_username}:#{browser.proxy_password}@" : ""
      "#{browser.proxy_type}://#{auth}#{browser.proxy_host}:#{browser.proxy_port}"
    end
  end
end
