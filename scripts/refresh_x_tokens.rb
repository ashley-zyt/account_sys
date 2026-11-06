# X 发文 token 定时刷新脚本
#
# 背景：发文模块（机器端经 /api/v1/x_tokens/latest 取 access_token 调 X API 发推）
#       依赖 x_account_credentials 的 token。X 的 refresh_token 有效期与「最后使用
#       时间」相关，长期不刷会自然过期。本脚本定时刷新，保持 refresh 链活性，
#       并在 token 失效时尽早暴露（置 failed），让运营有时间重新授权。
#
# 范围：auth_status = authorized 且账号状态 = 正常（发文在用的账号才刷，
#       KOL 触达已切浏览器模拟、不依赖 token，不在范围内）。
#
# 策略：
#   - token_expires_at 为空或距过期不足 1 小时 → 调 XAuthService.refresh_access_token
#     （access_token 寿命约 2 小时，每 6 小时跑一次必命中）
#   - 刷新成功：更新 access_token / refresh_token（轮换）/ token_expires_at
#   - 刷新失败：凭证据实置 failed（现有机制），列入报告，需人工重新授权
#
# 用法：
#   bundle exec rails runner scripts/refresh_x_tokens.rb
#   crontab（每 6 小时）：
#   0 */6 * * * cd /mnt/account_sys && bundle exec rails runner scripts/refresh_x_tokens.rb >> log/x_token_refresh.log 2>&1

scope = XCredential.authorized.joins(:account).where(accounts: { status: :正常 })

total   = scope.count
refreshed = 0
skipped   = 0
failed    = []
failed_accounts = []

puts "X token 定时刷新开始：范围内 #{total} 个（#{Time.current.strftime('%Y-%m-%d %H:%M:%S')}）"

scope.find_each do |xc|
  # 距过期超过 1 小时的跳过（理论上每 6 小时跑一次都会命中）
  if xc.token_expires_at.present? && xc.token_expires_at > 1.hour.from_now
    skipped += 1
    next
  end

  result = XAuthService.refresh_access_token(xc.account)
  if result[:success]
    refreshed += 1
    puts "[刷新成功] account_id=#{xc.account_id}"
  else
    # refresh_access_token 内部已把失效的置为 failed
    failed << xc.account_id
    failed_accounts << xc.account
    puts "[刷新失败] account_id=#{xc.account_id}：#{result[:message]}"
  end

  sleep 1 # 温和限速，避免批量请求触发 X 风控
end

puts '------------------------------------------------------------'
puts "完成：范围内 #{total}，本次刷新 #{refreshed}，未到刷新时间 #{skipped}，刷新失败 #{failed.size}"
if failed_accounts.any?
  puts '刷新失败清单（token 已失效，发文会失败，需重新授权）：'
  failed_accounts.each do |a|
    puts "  account_id=#{a.id} platform=#{a.platform}"
  end
end
