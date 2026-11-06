# 一次性脚本：解锁「无法联系」KOL 下被自动停用的 X/IG 渠道
#
# 背景：排查确认 unreachable KOL 名下 305 个停用渠道全部无人工 dm_blocked_reason 标记，
#       是 x_api 时代发送失败被自动停用误杀的（渠道本身可能没问题）。
#       浏览器模拟通道恢复后，值得退回「未联系」重新触达。
#
# 安全网：即使对方真的不可私信，重新发送失败后会走现有逻辑自动再停用渠道、
#         KOL 回「无法联系」，不会造成反复骚扰。
#
# 用法：
#   预览： bundle exec rails runner scripts/unlock_auto_disabled_contacts.rb
#   执行： EXEC=1 bundle exec rails runner scripts/unlock_auto_disabled_contacts.rb

PHASE_EXEC = ENV['EXEC'] == '1'

contacts = KolContact.joins(:kol)
                     .where(kols: { status: :unreachable })
                     .where(platform: KolContact::ENABLED_PLATFORMS, messaging_enabled: true)
                     .where(status: :disabled, dm_blocked_reason: nil)

kol_ids = contacts.distinct.pluck(:kol_id)
puts "将解锁 #{contacts.count} 个自动停用渠道，涉及 #{kol_ids.size} 个无法联系 KOL（#{PHASE_EXEC ? '执行模式' : '预览模式'}）"

exit unless PHASE_EXEC

contacts.find_each do |c|
  c.update!(status: :active, monitor_until: nil, next_poll_at: nil)
end

Kol.where(id: kol_ids, status: :unreachable).find_each do |k|
  k.update!(status: :pending, next_action_at: nil)
end

puts "完成：#{kol_ids.size} 个 KOL 已转「待联系」，解锁的渠道将参与下一轮自动触达"
