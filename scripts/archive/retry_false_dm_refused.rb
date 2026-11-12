# 诊断并重试「发送账号风险被误判为对方拒绝私信」而停用的联系方式
#
# 背景：修复 classify_failure 前，X API 发私信遇到 403 一律判「对方拒绝私信(dm_refused)」
#   并停用联系方式。但其中一部分其实是「发送账号有风险（如被 X 限流，发什么都 403 not permitted）」，
#   不是对方拒绝。这些被误判的联系方式需要恢复并重新触达。
#
# 区分依据：发送账号。风险账号导致的「对方拒绝私信」停用 = 误判；
#   正常账号导致的才是真拒绝。风险账号特征 = 「对方拒绝私信」失败次数异常多。
#   （注：修复后 account_risk 不再记「对方拒绝私信」，只记 detail，不会被本脚本误匹配。）
#
# 用法（在 account_sys 服务器上跑）：
#   预览（只统计，不改数据）：
#     bundle exec rails runner scripts/retry_false_dm_refused.rb
#   恢复指定账号导致的误判：
#     bundle exec rails runner scripts/retry_false_dm_refused.rb confirm --accounts=541
#   自动恢复疑似风险账号（失败次数 >= 阈值）：
#     bundle exec rails runner scripts/retry_false_dm_refused.rb confirm --auto --threshold=10

require 'set'

confirm = ARGV.include?('confirm')

threshold = 10
account_filter = nil
auto = false
ARGV.each do |a|
  if a.start_with?('--accounts=')
    account_filter = a.split('=', 2)[1].split(',').map(&:to_i).reject(&:zero?)
  elsif a.start_with?('--threshold=')
    threshold = a.split('=', 2)[1].to_i
    threshold = 10 if threshold <= 0
  elsif a == '--auto'
    auto = true
  end
end

# 所有「对方拒绝私信」失败消息
refused_msgs = KolMessage.where(direction: :outgoing, status: :sent_failed)
                        .where("error_msg LIKE '%对方拒绝私信%'")
                        .where.not(account_id: nil)

# 每个账号「对方拒绝私信」失败总次数
total_by_account = refused_msgs.group(:account_id).count

# 被停用的 contact id
disabled_ids = KolContact.where(status: :disabled).pluck(:id).to_set

# 每个账号导致的「停用 contact」集合（account_id => Set[contact_id]）
disabled_by_account = Hash.new { |h, k| h[k] = Set.new }
refused_msgs.where.not(kol_contact_id: nil)
            .pluck(:account_id, :kol_contact_id).each do |account_id, contact_id|
  next unless disabled_ids.include?(contact_id)
  disabled_by_account[account_id] << contact_id
end

puts "=== 「对方拒绝私信」导致的停用，按发送账号分组 ==="
puts "账号ID  账号名  「对方拒绝私信」失败总数  导致停用联系数  疑似风险(>=#{threshold})"
if disabled_by_account.empty?
  puts "  （无）"
end
disabled_by_account.sort_by { |_, ids| -ids.size }.each do |account_id, contact_ids|
  account = Account.find_by(id: account_id)
  name = account&.account_name || '(账号已删除)'
  total = total_by_account[account_id].to_i
  risk = total >= threshold ? '⚠️' : ''
  puts "  #{account_id.to_s.ljust(6)}  #{name.to_s.ljust(26)}  #{total.to_s.rjust(4)}  #{contact_ids.size.to_s.rjust(6)}  #{risk}"
end

# 确定目标账号
target_ids = account_filter || (auto ? disabled_by_account.keys.select { |id| total_by_account[id].to_i >= threshold } : [])

if confirm
  if target_ids.empty?
    puts "\n未指定要恢复的账号。用法：confirm --accounts=541 或 confirm --auto"
  else
    restored_contacts = Set.new
    requeued_kols = Set.new
    disabled_by_account.each do |account_id, contact_ids|
      next unless target_ids.include?(account_id)
      contact_ids.each do |cid|
        contact = KolContact.find_by(id: cid)
        next if contact.nil? || contact.active?
        contact.update!(status: :active)
        restored_contacts << cid
        kol = contact.kol
        next if kol.nil?
        # 恢复后若 KOL 因无可私信联系方式而处于终态，重新入队触达
        if %w[unreachable unresponsive].include?(kol.status.to_s) && kol.enqueue!
          requeued_kols << kol.id
        end
      end
    end
    puts "\n完成：恢复 #{restored_contacts.size} 个联系方式，重新入队 #{requeued_kols.size} 个 KOL"
    puts "这些联系方式将重新进入触达队列，由正常账号重新发私信验证："
    puts "  - 发成功 → 之前确实是误判"
    puts "  - 仍「对方拒绝私信」→ 之前是真拒绝（会被再次正确停用）"
  end
else
  puts "\n以上为预览，未改动任何数据。"
  puts "恢复误判：bundle exec rails runner scripts/retry_false_dm_refused.rb confirm --accounts=541"
  puts "（或 confirm --auto 自动恢复失败数 >= #{threshold} 的疑似风险账号）"
end
