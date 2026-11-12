# 验证 KOL 回复轮询衰减机制
# 用法：bundle exec rails runner scripts/test_poll_decay.rb

def interval_for(elapsed)
  KolReplyPoller.send(:poll_interval_hours, elapsed)
end

puts "=== 1. 衰减函数边界验证（elapsed -> 下次间隔）==="
[0, 12, 23, 24, 48, 95, 96, 120, 168, 240, 312].each do |e|
  puts "  elapsed=%3dh -> %2dh/次" % [e, interval_for(e)]
end
puts "  （预期：<24 是 12；24~95 是 24；>=96 是 72）"
puts

puts "=== 2. 当前 contacting 联系方式轮询状态 ==="
contacts = KolContact.where(status: :contacting).order(:id)
if contacts.none?
  puts "  （无 contacting 联系方式）"
else
  contacts.each do |c|
    sent = c.last_sent_at ? c.last_sent_at.strftime('%m-%d %H:%M') : 'nil(历史)'
    nxt  = c.next_poll_at ? c.next_poll_at.strftime('%m-%d %H:%M') : 'nil(待首轮)'
    mon  = c.monitor_until ? c.monitor_until.strftime('%m-%d') : 'nil'
    puts "  contact=#{c.id} platform=#{c.platform} sent=#{sent} next_poll=#{nxt} monitor_until=#{mon}"
  end
end
