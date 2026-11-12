# 列出「无法解析 user_id」停用的 twitter 联系方式（疑似 @username 失效）
#
# 背景：历史数据里「无法解析对方 X user_id」可能是两种情况：
#   ① @username 真的改名/注销（真失效，需更新联系方式）
#   ② 当时查 user_id 的账号 token 失效（误判，重新验证可恢复）
# 本脚本只负责「列出候选清单」，供运营去 X 页面逐个查证后再人工处理（用编辑表单
# 更新 url，或标记「不可私信原因 = @username 失效」）。
#
# 用法：
#   bundle exec rails runner scripts/list_unresolved_usernames.rb

msgs = KolMessage.where(direction: :outgoing, status: :sent_failed)
                .where("error_msg LIKE ?", "%无法解析对方 X user_id%")

contact_ids = msgs.where.not(kol_contact_id: nil).distinct.pluck(:kol_contact_id)
contacts = KolContact.where(id: contact_ids, status: :disabled, platform: :twitter)
                     .includes(:kol).order(:id)

puts "=== 疑似 @username 失效（无法解析 user_id）的联系方式 ==="
puts "共 #{contacts.size} 个，请去 X 页面逐个验证 @username 是否还有效"
puts
contacts.each do |c|
  puts "  contact##{c.id}  KOL##{c.kol_id} #{c.kol&.name}  url=#{c.url}"
end
puts
puts "查证后处理："
puts "  - @username 还在 → 可能是 token 失效误判，跑 reverify_unreachable_kols.rb 重新验证"
puts "  - @username 改名/注销 → 编辑 KOL 更新 url（新 username），或标记「不可私信原因 = @username 失效」"
