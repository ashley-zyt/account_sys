# 历史 contacting 联系方式：补 last_sent_at + 监测窗口从旧规则(30天)修正为新规则(14天) + 初始化 next_poll_at
# 用法（migration 后跑一次）：
#   bundle exec rails runner scripts/backfill_kol_poll_fields.rb          # 预览
#   bundle exec rails runner scripts/backfill_kol_poll_fields.rb confirm  # 执行

OLD_MONITOR_DAYS = 30
NEW_MONITOR_DAYS = KolScheduler.reply_monitor_days # 14

confirm = ARGV.include?('confirm')

targets = KolContact.where(status: :contacting).where.not(monitor_until: nil).order(:id)

puts "待修正的 contacting 联系方式：#{targets.count} 个"
targets.each do |c|
  sent_at = c.monitor_until - OLD_MONITOR_DAYS.days
  new_mon = sent_at + NEW_MONITOR_DAYS.days
  nxt = [sent_at + 12.hours, Time.current].max
  puts "  contact=#{c.id} platform=#{c.platform} 旧monitor=#{c.monitor_until.strftime('%m-%d')} -> 新monitor=#{new_mon.strftime('%m-%d')} sent=#{sent_at.strftime('%m-%d %H:%M')} next_poll=#{nxt.strftime('%m-%d %H:%M')}"
  next unless confirm
  c.update!(last_sent_at: sent_at, monitor_until: new_mon, next_poll_at: nxt)
end

if confirm
  puts "已执行修正 #{targets.count} 个"
else
  puts "以上为预览，确认后加 confirm 参数执行"
end
