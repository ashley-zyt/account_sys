# 导出：指纹浏览器 → 代理(proxy_host) → 运营机器 → 正常账号/平台 → 近三次浏览量是否全为0
#
# 运行方式（在项目根目录 d:\ashly\account_sys 下执行）：
#   bin/rails runner scripts/export_browser_accounts.rb
#   或  bundle exec rails runner scripts/export_browser_accounts.rb
#
# 输出：tmp/browser_accounts_export_<时间戳>.csv（UTF-8 带 BOM，Excel 可直接打开）
#
# 说明：按指纹浏览器分组；每个浏览器前插入一行明显的分隔标记，
#       方便在 Excel 中快速区分「哪些账号属于同一个浏览器」。

require "csv"

timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
out_path  = Rails.root.join("tmp", "browser_accounts_export_#{timestamp}.csv")

headers = %w[
  指纹浏览器名
  proxy_host(代理)
  运营机器
  账号名
  平台
  近三次浏览量是否全为0
]

# 近三次浏览量：取该账号最近 3 条发文记录（按 post_date 倒序），
# 判断 views_count 是否全部为 0。
#   无发文记录 => 无记录
#   全部为 0   => 是
#   存在 > 0   => 否
def recent_views_zero_label(account)
  recent = account.post_stats
                  .order(post_date: :desc, id: :desc)
                  .limit(3)
                  .pluck(:views_count)

  return "无记录" if recent.empty?
  recent.all? { |v| v.to_i == 0 } ? "是" : "否"
end

# 一条「指纹浏览器」的分隔标记行
def browser_marker(profile_name, proxy_host, machine_ip)
  name  = profile_name.presence || "（未绑定浏览器）"
  proxy = proxy_host.presence || "-"
  ip    = machine_ip.presence || "-"
  "══════ 指纹浏览器：#{name} ｜ 代理：#{proxy} ｜ 机器：#{ip} ══════"
end

# 输出行的集合：普通数据行为 6 列；分隔标记行第 1 列放标记文本、其余留空
output_rows = []
prev_browser_id = Object.new  # 用一个不可能相等的初始值，保证第一个浏览器也会出标记

# 只导出「正常」状态的账号（Account.active 即 status = 正常）
accounts = Account.active
                  .includes(:browser)
                  .order(:browser_id, :account_name)
                  .to_a

accounts.each do |account|
  browser = account.browser
  bid = account.browser_id

  # 切换到新浏览器时，插入一条明显的分隔标记
  if bid != prev_browser_id
    output_rows << [browser_marker(browser&.profile_name, browser&.proxy_host, browser&.machine_ip), "", "", "", "", ""]
    prev_browser_id = bid
  end

  output_rows << [
    browser&.profile_name,
    browser&.proxy_host,
    browser&.machine_ip,
    account.account_name,
    account.platform.to_s,
    recent_views_zero_label(account)
  ]
end

# 写入 CSV，文件头部写入 BOM 以兼容 Excel 打开中文
File.open(out_path, "wb") do |f|
  f.write("\xEF\xBB\xBF")
  csv = CSV.new(f)
  csv << headers
  output_rows.each { |row| csv << row }
end

distinct_browsers = accounts.map(&:browser_id).compact.uniq.size

puts "导出完成：共 #{accounts.size} 个正常账号，涉及 #{distinct_browsers} 个指纹浏览器"
puts "文件路径：#{out_path}"
