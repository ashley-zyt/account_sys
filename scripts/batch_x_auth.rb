# ===== 批量发起 X（Twitter）API 认证 =====
#
# 对一批 twitter 账号逐个调用 XAuthService.start_authorization：
#   生成 PKCE → 记录「认证中」→ 下发机器端打开授权页（机器端自动点击授权按钮）。
#   机器端截到 code 后会自动回调 account_sys 换 token（无需本脚本干预）。
#   按「每 interval 秒触发一个」的节奏逐个下发，避免一次性铺开太多浏览器。
#
# 用法（在 account_sys 服务器上跑）：
#   预览（只列出目标账号，不发起任何认证）：
#     bundle exec rails runner scripts/batch_x_auth.rb
#   执行（按节奏逐个发起认证）：
#     bundle exec rails runner scripts/batch_x_auth.rb confirm
#
# 可选参数（放 confirm 后面即可，顺序不限）：
#   --ids=1,2,3        只处理指定账号 ID（逗号分隔；此时不限平台/状态）
#   --only-unauthed    只处理「未认证」的账号（跳过已 authorized 的）
#   --limit=N          最多处理 N 个（分批跑时用）
#   --all-status       包含非「正常」状态的账号（默认只处理正常状态）
#   --interval=N       每触发一个后等待 N 秒再触发下一个（默认 30，即半分钟一个）

# ---------- 参数解析 ----------
args = ARGV.dup
confirm = args.delete('confirm') ? true : false
opts = {}
args.each do |a|
  if a =~ /\A--ids=(.+)\z/
    opts[:ids] = $1.split(',').map(&:strip).map(&:to_i).reject(&:zero?)
  elsif a == '--only-unauthed'
    opts[:only_unauthed] = true
  elsif a =~ /\A--limit=(\d+)\z/
    opts[:limit] = $1.to_i
  elsif a == '--all-status'
    opts[:all_status] = true
  elsif a =~ /\A--interval=(\d+)\z/
    opts[:interval] = $1.to_i
  end
end

# ---------- 筛选目标账号 ----------
scope = if opts[:ids].present?
  Account.where(id: opts[:ids])
else
  base = Account.where(platform: :twitter)
  opts[:all_status] ? base : base.active
end

accounts = scope.order(:id).to_a

accounts = accounts.reject { |a| a.x_credential&.authorized? } if opts[:only_unauthed]
accounts = accounts.first(opts[:limit]) if opts[:limit] && opts[:limit] > 0

def x_auth_label(a)
  xc = a.x_credential
  return '未认证' if xc.nil?
  return '已认证' if xc.authorized?
  case xc.auth_status
  when 'authorizing' then '认证中'
  when 'failed' then '失败'
  else '未认证'
  end
end

puts "==== #{confirm ? '执行' : '预览'}：批量发起 X 认证 ===="
puts "目标 twitter 账号 #{accounts.size} 个"
puts

if accounts.empty?
  puts '没有符合条件的账号。'
  exit
end

# ---------- 预览清单 ----------
accounts.each do |a|
  puts format('  #%-6d %-24s 状态=%-8s 浏览器=%-18s X认证=%-6s',
              a.id, a.account_name.to_s, a.status.to_s, a.browser&.profile_name.to_s, x_auth_label(a))
end

# ---------- 执行 ----------
if confirm
  interval = opts[:interval] && opts[:interval] > 0 ? opts[:interval] : 30
  ok = 0
  fail_list = []
  accounts.each_with_index do |a, idx|
    begin
      r = XAuthService.start_authorization(a)
      if r[:success]
        ok += 1
        puts "  OK #%d %s：%s" % [a.id, a.account_name, r[:message]]
      else
        fail_list << [a.id, a.account_name, r[:message]]
        puts "  NG #%d %s：%s" % [a.id, a.account_name, r[:message]]
      end
    rescue => e
      fail_list << [a.id, a.account_name, e.message]
      puts "  NG #%d %s：异常 %s" % [a.id, a.account_name, e.message]
    end

    # 半分钟触发一个：处理完当前账号后等 interval 秒再触发下一个（最后一个不等）
    sleep(interval) if idx < accounts.size - 1
  end

  puts
  puts "成功发起 #{ok} 个，失败 #{fail_list.size} 个"
  if fail_list.any?
    puts '失败明细：'
    fail_list.each { |id, name, msg| puts "  - #%d %s：%s" % [id, name, msg] }
  end
  puts '提醒：机器端会自动点击授权；截到 code 后自动回调换 token。'
else
  puts
  puts '⚠️ 以上为预览，未发起任何认证。确认后执行：'
  puts '  bundle exec rails runner scripts/batch_x_auth.rb confirm'
  puts '  （可加 --only-unauthed 只补未认证的、--limit=20 分批、--interval=30 调整节奏、--ids=1,2,3 指定账号）'
end
