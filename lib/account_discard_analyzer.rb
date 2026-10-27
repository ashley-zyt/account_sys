# 弃用账号分析器
#
# 输入一批要弃用的账号 ID，按代理（浏览器）分组打印：
#   1. 该代理下要弃用的账号（ID + 名称 + 平台）
#   2. 该代理下除弃用外，还剩多少个「正常状态」的账号（ID + 名称 + 平台）
#
# 用法：AccountDiscardAnalyzer.analyze([1, 2, 3])
class AccountDiscardAnalyzer
  class << self
    def analyze(account_ids)
      ids = Array(account_ids).map(&:to_i).reject(&:zero?)
      return puts("未提供账号 ID") if ids.empty?

      accounts = Account.where(id: ids).includes(:browser).order(:id)
      browser_ids = accounts.map(&:browser_id).compact.uniq

      puts "\n===== 弃用账号使用的代理 ====="
      browser_ids.each do |bid|
        b = Browser.find_by(id: bid)
        next if b.nil?

        discard = accounts.select { |a| a.browser_id == bid }
        remaining = b.accounts.where(status: Account.statuses["正常"]).where.not(id: ids).order(:id)

        puts "\n代理 #{proxy_text(b)}（浏览器 #{b.profile_name}）"

        puts "  弃用账号（#{discard.size} 个）："
        discard.each { |a| puts "    #{a.id} | #{a.account_name}（#{a.platform}）" }

        puts "  剩余正常账号（#{remaining.count} 个）："
        if remaining.any?
          remaining.each { |a| puts "    #{a.id} | #{a.account_name}（#{a.platform}）" }
        else
          puts "    （无）"
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
