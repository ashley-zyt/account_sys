# 探测 X 发私信的完整错误响应 —— 确认 body 里有没有「错误码 code」字段
#
# 用法（在 account_sys 服务器上跑）：
#   bundle exec rails runner scripts/probe_x_dm_error.rb <账号ID> <@username>
#
#   参数1 = 一个「正常」账号 ID（有 dm.write 权限、能正常发 DM 的，比如 478）
#   参数2 = 对方 @username（要测试的目标，比如 @puffer_finance、@dYdX）
#
# 目的：抓取 X 返回的完整 raw / body，看 errors 里有没有 code 字段，
#   用于确认「对方没开私信 / 私信要验证」这类失败能否被 code 精确区分。

account_id = ARGV[0].to_i
username = ARGV[1].to_s.sub(/\A@/, '')

account = Account.find_by(id: account_id)
abort "账号 #{account_id} 不存在" unless account
abort '请提供对方 @username（第二个参数）' if username.blank?

token = XAuthService.access_token_for(account)
abort "账号 #{account.id} 拿不到有效 token" if token.blank?

puts "账号: #{account.id} #{account.account_name}"
puts "目标: @#{username}"
puts

# 1. 查 user_id
r = XApi.user_by_username(access_token: token, username: username)
unless XApi.success?(r)
  puts "✗ 查用户失败: HTTP #{r[:code]}"
  puts "  body = #{r[:body].inspect}"
  puts "  raw  = #{r[:raw]}"
  exit
end
uid = r.dig(:body, 'data', 'id')
puts "✓ user_id = #{uid}"
puts

# 2. 发私信（重点看这里的完整响应）
r2 = XApi.send_dm(access_token: token, participant_id: uid, text: 'hello, this is a probe')
puts '发私信响应:'
puts "  HTTP code = #{r2[:code]}"
puts "  body = #{r2[:body].inspect}"
puts "  raw  = #{r2[:raw]}"
puts
puts '重点看 body 里的 errors[0].code（如有）：'
puts '  63=对方被暂停  150=仅关注者可私信  326=账号被锁  261=App无写权限  220=凭证无权限'
