# 弃用账号分析器（导出 Excel）
#
# 输入一批要弃用的账号 ID，导出 .xlsx：
#   Sheet1「弃用账号清单」：每个弃用账号对应的浏览器（profile_name）与代理
#   Sheet2「浏览器正常账号」：每个涉及到的浏览器下，还有哪些「正常状态」的账号（平台 + 账号名）
#
# 用法：AccountDiscardAnalyzer.analyze([1, 2, 3])
class AccountDiscardAnalyzer
  class << self
    def analyze(account_ids)
      ids = Array(account_ids).map(&:to_i).reject(&:zero?)
      return puts("未提供账号 ID") if ids.empty?

      require "write_xlsx"

      accounts = Account.where(id: ids).includes(:browser).order(:id)
      browser_ids = accounts.map(&:browser_id).compact.uniq
      browsers = Browser.where(id: browser_ids).index_by(&:id)

      timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
      path = Rails.root.join("tmp", "discard_accounts_#{timestamp}.xlsx").to_s

      workbook = WriteXLSX.new(path)
      header_fmt = workbook.add_format(bold: 1, bg_color: "#dbeafe")

      # Sheet1：弃用账号清单
      ws1 = workbook.add_worksheet("弃用账号清单")
      headers1 = ["账号ID", "账号名", "平台", "状态", "浏览器", "代理"]
      headers1.each_with_index { |h, c| ws1.write(0, c, h, header_fmt) }
      accounts.each_with_index do |a, i|
        b = a.browser
        row = [a.id, a.account_name, a.platform.to_s, a.status, b&.profile_name, proxy_text(b)]
        row.each_with_index { |v, c| ws1.write(i + 1, c, v) }
      end

      # Sheet2：浏览器正常账号
      ws2 = workbook.add_worksheet("浏览器正常账号")
      headers2 = ["浏览器", "代理", "正常账号ID", "正常账号名", "平台"]
      headers2.each_with_index { |h, c| ws2.write(0, c, h, header_fmt) }
      r = 1
      browser_ids.each do |bid|
        b = browsers[bid]
        next if b.nil?

        active = b.accounts.where(status: Account.statuses["正常"]).order(:platform, :id)
        if active.empty?
          row = [b.profile_name, proxy_text(b), "", "（无正常账号，可一并弃用）", ""]
          row.each_with_index { |v, c| ws2.write(r, c, v) }
          r += 1
        else
          active.each do |a|
            row = [b.profile_name, proxy_text(b), a.id, a.account_name, a.platform.to_s]
            row.each_with_index { |v, c| ws2.write(r, c, v) }
            r += 1
          end
        end
      end

      workbook.close

      puts "导出完成：弃用账号 #{accounts.size} 个，涉及浏览器 #{browser_ids.size} 个"
      puts "文件路径：#{path}"
      path
    end

    # 拼代理展示字符串：type://user:pass@host:port（无认证则 type://host:port）
    def proxy_text(browser)
      return '-' if browser.nil? || browser.proxy_host.blank?
      auth = browser.proxy_username.present? ? "#{browser.proxy_username}:#{browser.proxy_password}@" : ""
      "#{browser.proxy_type}://#{auth}#{browser.proxy_host}:#{browser.proxy_port}"
    end
  end
end
