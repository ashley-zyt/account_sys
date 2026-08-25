# 导出：指纹浏览器 → 运营机器IP → 正常账号/平台 → 近三次浏览量是否为0
#
# 运行方式（在项目根目录 d:\ashly\account_sys 下执行）：
#   bin/rails runner scripts/export_browser_accounts.rb
#   或  bundle exec rails runner scripts/export_browser_accounts.rb
#
# 输出：tmp/browser_accounts_export_<时间戳>.csv（UTF-8 带 BOM，Excel 可直接打开）

require "csv"

timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
out_path  = Rails.root.join("tmp", "browser_accounts_export_#{timestamp}.csv")

headers = %w[
  指纹浏览器名
  运营机器IP
  正常账号
  平台
  近三次浏览量是否全为0
  最近三次浏览量(新→旧)
]

# 近三次浏览量：取该账号最近 3 条发文记录（按 post_date 倒序），
# 判断 views_count 是否全部为 0。
#   无发文记录 => 无记录
#   全部为 0   => 是
#   存在 > 0   => 否
def recent_views_info(account)
  recent = account.post_stats
                  .order(post_date: :desc, id: :desc)
                  .limit(3)
                  .pluck(:views_count)

  if recent.empty?
    ["无记录", ""]
  else
    all_zero = recent.all? { |v| v.to_i == 0 }
    [all_zero ? "是" : "否", recent.map(&:to_i).join(", ")]
  end
end

rows = []

# 只导出「正常」状态的账号（Account.active 即 status = 正常）
Account.active
       .includes(:browser)
       .order(:browser_id, :account_name)
       .find_each do |account|
  browser = account.browser
  all_zero_label, views_str = recent_views_info(account)

  rows << [
    browser&.profile_name,
    browser&.machine_ip,
    account.account_name,
    account.platform.to_s,
    all_zero_label,
    views_str
  ]
end

# 写入 CSV，文件头部写入 BOM 以兼容 Excel 打开中文
File.open(out_path, "wb") do |f|
  f.write("\xEF\xBB\xBF")
  csv = CSV.new(f)
  csv << headers
  rows.each { |row| csv << row }
end

distinct_browsers = rows.map { |r| r[0] }.compact.uniq.size

puts "导出完成：共 #{rows.size} 个正常账号，涉及 #{distinct_browsers} 个指纹浏览器"
puts "文件路径：#{out_path}"
