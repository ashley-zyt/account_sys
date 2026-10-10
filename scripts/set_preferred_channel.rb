# 批量设置账号「首选发布渠道」（accounts.publish_channel）
#
# 用法：
#   bundle exec rails runner scripts/set_preferred_channel.rb x_api 1,2,3,4
#   bundle exec rails runner scripts/set_preferred_channel.rb postforme 5,6,7
#   bundle exec rails runner scripts/set_preferred_channel.rb ag_center 1,2,3
#   bundle exec rails runner scripts/set_preferred_channel.rb default 1,2,3   # 清空 = 走默认链
#
# 渠道取值：ag_center / postforme / x_api / default(清空)

channel = ARGV[0].to_s.strip.downcase
ids = ARGV[1].to_s.split(',').map(&:to_i).reject(&:zero?)

abort '用法: scripts/set_preferred_channel.rb <渠道> <账号ID列表,逗号分隔>' if ids.empty?

value =
  case channel
  when 'default', 'nil', ''
    nil
  when 'ag_center', 'postforme', 'x_api'
    Account.publish_channels[channel]
  else
    abort "未知渠道 #{channel}，可选：ag_center / postforme / x_api / default"
  end

count = Account.where(id: ids).update_all(publish_channel: value)
puts "已将 #{count} 个账号的首选渠道设为 #{channel}（value=#{value.inspect}）"
