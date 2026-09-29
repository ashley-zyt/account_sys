# ===== 诊断 X 认证状态（配合批量授权排查「该账号未发起认证」） =====
# 用法：
#   查单个账号（默认 202）：
#     bundle exec rails runner scripts/diagnose_x_auth_status.rb 202
#   只看全量状态分布：
#     bundle exec rails runner scripts/diagnose_x_auth_status.rb

account_id = ARGV[0]

if account_id.present?
  a = Account.find_by(id: account_id)
  if a.nil?
    puts "账号 #{account_id} 不存在（或已被软删除）"
  else
    xc = a.x_credential
    puts "账号 #{a.id}（#{a.account_name}）"
    if xc.nil?
      puts "  ✗ 无 x_credential 记录 —— 说明从未成功发起过认证（start_authorization 没跑到或被删）"
    else
      puts "  auth_status     = #{xc.auth_status}"
      puts "  x_user_id       = #{xc.x_user_id.inspect}"
      puts "  code_verifier   = #{xc.code_verifier.present? ? '存在' : '空'}"
      puts "  state           = #{xc.state.present? ? '存在' : '空'}"
      puts "  access_token    = #{xc.access_token.present? ? '存在' : '空'}"
      puts "  token_expires_at= #{xc.token_expires_at}"
      puts "  updated_at      = #{xc.updated_at}"
    end
  end
  puts
end

puts "=== 全量 X 认证状态分布 ==="
XCredential.group(:auth_status).count.each { |k, v| puts "  #{k}: #{v}" }
puts

puts "=== 卡在 authorizing（认证中）的账号 —— 机器端可能已回调但换 token 失败 ==="
authorizing = XCredential.where(auth_status: :authorizing).order(:account_id)
if authorizing.none?
  puts "  （无）"
else
  authorizing.each do |xc|
    puts "  account=#{xc.account_id} updated_at=#{xc.updated_at} code_verifier=#{xc.code_verifier.present? ? '有' : '空'}"
  end
end
