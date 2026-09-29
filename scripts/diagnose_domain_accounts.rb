# ===== 盘点每个领域的可用账号覆盖（KOL X 认证触达用）=====
# 输出：每个领域的账号总数 / 正常数 / twitter 数 / 已认证 X 数，对照 KOL 待联系分布，
#       重点标出「有待联系 KOL 但缺 X 认证账号」的领域。
# 用法：
#   bundle exec rails runner scripts/diagnose_domain_accounts.rb

theme_domains = Theme.pluck(:name, :domain_id).to_h
accounts = Account.all.to_a
domains = Domain.order(:id).to_a

puts "==== 领域账号覆盖盘点 ===="
puts
puts format('%-5s %-18s %-8s %-8s %-9s %-8s %-10s',
            '领域ID', '领域', '正常账号', 'twitter', 'X已认证', 'KOL总数', '待联系KOL')
puts '-' * 76

shortage = []
domains.each do |d|
  domain_accounts = accounts.select { |a| theme_domains[a.theme] == d.id }
  active   = domain_accounts.select { |a| a.status == '正常' }
  twitter  = active.select { |a| a.platform == 'twitter' }
  x_authed = twitter.select { |a| a.x_credential&.authorized? }

  kol_count    = Kol.where(domain_id: d.id).count
  kol_pending  = Kol.where(domain_id: d.id).where(status: [:pending, :contacting]).count

  puts format('%-5d %-18s %-8d %-8d %-9d %-8d %-10d',
              d.id, d.name.to_s, active.size, twitter.size, x_authed.size, kol_count, kol_pending)

  if kol_pending > 0 && x_authed.empty?
    shortage << "#{d.name}（待联系 KOL #{kol_pending} 个，但无 X 认证 twitter 账号）"
  end
end

puts
puts "==== 缺口的领域 ===="
if shortage.empty?
  puts "（无）—— 所有有待联系 KOL 的领域都有已认证 X 的 twitter 账号。"
else
  shortage.each { |s| puts "  ⚠️ #{s}" }
end
