# 验证 117 域名 + 鉴权是否生效（域名不带端口，走 80）
#
# 运行：bundle exec rails runner scripts/verify_auth_and_domain.rb
#
# 只读、不改任何数据。共 5 个维度：
#   1. 密钥配置（.env 的 REMOTE_API_KEY / REMOTE_API_SECRET）
#   2. 域名 DNS 解析（ag117.juzhiic.com）
#   3. /health 连通性（无需鉴权，验证域名可达）
#   4. 鉴权签名（只读接口 /api/browser/locked，200=鉴权通过，401=鉴权失败）
#   5. 数据库 machine_ip 迁移（残留 IP 应为 0）
require 'resolv'
require 'net/http'
require 'uri'

# 当前只验证 117（15 尚未部署）；域名不带端口，走 80
DOMAIN = "ag117.juzhiic.com"

puts "===== 1. 密钥配置检查 ====="
api_key    = ENV['REMOTE_API_KEY'].to_s
api_secret = ENV['REMOTE_API_SECRET'].to_s
if api_key.present? && api_secret.present?
  puts "[OK]   REMOTE_API_KEY / REMOTE_API_SECRET 已配置（长度 #{api_key.length}/#{api_secret.length}）"
else
  puts "[FAIL] 密钥未配置！请在 .env 设置 REMOTE_API_KEY 和 REMOTE_API_SECRET 后重启服务"
end

puts "\n===== 2. 域名 DNS 解析检查 ====="
begin
  ip = Resolv.getaddress(DOMAIN)
  puts "[OK]   #{DOMAIN} -> #{ip}"
rescue => e
  puts "[FAIL] #{DOMAIN} 解析失败: #{e.message}"
end

puts "\n===== 3. /health 连通性检查（无需鉴权，验证域名可达）====="
begin
  uri  = URI("https://#{DOMAIN}/health")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 5
  http.read_timeout = 5
  resp = http.get(uri.request_uri)
  puts "[OK]   https://#{DOMAIN}/health -> HTTP #{resp.code}"
rescue => e
  puts "[FAIL] https://#{DOMAIN}/health 连接失败: #{e.message}"
end

puts "\n===== 4. 鉴权签名验证（只读接口 /api/browser/locked）====="
if api_key.blank? || api_secret.blank?
  puts "[SKIP] 密钥未配置，鉴权验证结果不可信，请先解决第 1 项再重跑"
else
  begin
    resp = RemoteApiClient.get("https://#{DOMAIN}/api/browser/locked", open_timeout: 30, read_timeout: 100)
    case resp.code
    when '200'
      puts "[OK]   #{DOMAIN} /api/browser/locked -> HTTP 200（鉴权通过）"
    when '401'
      puts "[FAIL] #{DOMAIN} /api/browser/locked -> HTTP 401（鉴权失败：密钥错/签名错/时间戳偏移/nonce重放）"
    else
      puts "[WARN] #{DOMAIN} /api/browser/locked -> HTTP #{resp.code}（非预期状态码）"
    end
  rescue Net::ReadTimeout
    puts "[WARN] #{DOMAIN} /api/browser/locked 响应超时（接口本身较慢，不代表鉴权失败；若反复超时请确认服务端健康）"
  rescue => e
    puts "[FAIL] #{DOMAIN} 请求异常: #{e.message}"
  end
end

puts "\n===== 5. 数据库 machine_ip 迁移检查 ====="
%w[174.139.46.117 174.139.46.15].each do |ip|
  c = Browser.where(machine_ip: ip).count
  if c == 0
    puts "[OK]   browsers 中无残留 #{ip}"
  else
    puts "[FAIL] browsers 中仍有 #{c} 条 #{ip}（迁移 SQL 未执行或未生效）"
  end
end
domain_count = Browser.where(machine_ip: ['ag117.juzhiic.com', 'ag15.juzhiic.com']).count
puts "[INFO] 已迁移为域名的浏览器数: #{domain_count}"

puts "\n===== 完成 ====="
