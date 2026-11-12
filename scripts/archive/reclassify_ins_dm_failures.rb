# 按新规则回溯分类 Ins 私信失败记录，批量纠正「账号休眠 + 联系方式停用」
#
# 规则（与 browser_task_result_handler.classify_browser_send_failure 一致）：
#   error_msg 含「未登录 / not_logged_in / 登录失效」→ 账号问题 → 永久休眠账号
#   其余（IG_MSG3 未找到 Message 按钮 / IG_MSG2 页面不可用·链接失效/页面已删除 等）→ 对方问题 → 停用联系方式
#
# 用法（在 account_sys 服务器上跑）：
#   预览（只列出，不改数据）：
#     bundle exec rails runner scripts/reclassify_ins_dm_failures.rb
#   执行（休眠账号 + 停用联系方式 + 重算 KOL 状态）：
#     bundle exec rails runner scripts/reclassify_ins_dm_failures.rb confirm

confirm = ARGV.include?('confirm')

ACCOUNT_RISK_RE = /未登录|not_logged_in|登录失效/

messages = KolMessage.where(platform: :instagram, direction: :outgoing, status: :sent_failed).to_a

def account_risk?(error_msg)
  error_msg.to_s =~ ACCOUNT_RISK_RE
end

risk_msgs   = messages.select { |m| account_risk?(m.error_msg) }
target_msgs = messages.reject { |m| account_risk?(m.error_msg) }

risk_account_ids   = risk_msgs.map(&:account_id).compact.uniq
target_contact_ids = target_msgs.map(&:kol_contact_id).compact.uniq

puts "=== Ins 私信失败回溯分类 ==="
puts "失败总数: #{messages.size}"
puts "账号问题(未登录): #{risk_msgs.size} 条 → 涉及账号 #{risk_account_ids.size} 个"
puts "对方问题(其他):   #{target_msgs.size} 条 → 涉及联系方式 #{target_contact_ids.size} 个"
puts

puts "--- 错误信息分布（前 15 类，用于核对分类是否准确）---"
messages.group_by { |m| m.error_msg.to_s[0, 60] }
        .sort_by { |_, v| -v.size }
        .first(15)
        .each { |k, v| puts "  #{v.size} 条 | #{k}" }
puts

puts "--- 将永久休眠的账号（未登录）---"
Account.where(id: risk_account_ids).each do |a|
  puts "  ##{a.id} #{a.account_name} platform=#{a.platform} 当前休眠=#{a.kol_sleeping?}"
end
puts

puts "--- 将停用的联系方式（对方问题）---"
KolContact.where(id: target_contact_ids).includes(:kol).each do |c|
  puts "  contact##{c.id} KOL##{c.kol_id} #{c.kol&.name} #{c.url} 当前状态=#{c.status}"
end

if confirm
  # 1. 永久休眠账号
  n1 = Account.where(id: risk_account_ids)
              .update_all(kol_sleep_until: 100.years.from_now, updated_at: Time.current)
  # 2. 停用联系方式
  n2 = KolContact.where(id: target_contact_ids)
                 .update_all(status: KolContact.statuses[:disabled], updated_at: Time.current)
  # 3. 重算受影响 KOL：停用联系方式后，pending/contacting 且已无可私信渠道 → 无法联系
  kol_ids = KolContact.where(id: target_contact_ids).distinct.pluck(:kol_id)
  n3 = 0
  Kol.where(id: kol_ids, status: [:pending, :contacting]).includes(:kol_contacts).find_each do |kol|
    next if kol.has_outreachable_contacts?
    kol.update!(status: :unreachable, next_action_at: nil)
    n3 += 1
  end

  puts "\n完成：永久休眠 #{n1} 个账号，停用 #{n2} 个联系方式，标记无法联系 KOL #{n3} 个"
else
  puts "\n以上为预览，未改动任何数据。"
  puts "执行：bundle exec rails runner scripts/reclassify_ins_dm_failures.rb confirm"
end
