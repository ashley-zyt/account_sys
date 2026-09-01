# 验证「鉴权机制 + 域名变更」是否生效
#
# 运行：bundle exec rails runner scripts/verify_auth_and_domain.rb
#
# 只读、不改任何数据。共 5 个维度：
#   1. 密钥配置（.env 的 REMOTE_API_KEY / REMOTE_API_SECRET）
#   2. 域名 DNS 解析（ag117.juzhiic.com / ag15.juzhiic.com）
#   3. /health 连通性（无需鉴权，验证域名+端口可达）
#   4. 鉴权签名（只读接口 /api/browser/locked，200=鉴权通过，401=鉴权失败）
#   5. 数据库 machine_ip 迁移（残留 IP 应为 0）
require 'resolv'
require 'net/http'
require 'uri'

puts "===== 1. 密钥配置检查 ====="
api_key    = ENV['REMOTE_API_KEY'].to_s
api_secret = ENV['REMOTE_API_SECRET'].to_s
if api_key.present? && api_secret.present?
  puts "[OK]   REMOTE_API_KEY / REMOTE_API_SECRET 已配置（长度 #{api_key.length}/#{api_secret.length}）"
else
  puts "[FAIL] 密钥未配置！请在 .env 设置 REMOTE_API_KEY 和 REMOTE_API_SECRET 后重启服务"
end

puts "\n===== 2. 域名 DNS 解析检查 ====="
DOMAINS = %w[ag117.juzhiic.com ag15.juzhiic.com].freeze
DOMAINS.each do |domain|
  begin
    ip = Resolv.getaddress(domain)
    puts "[OK]   #{domain} -> #{ip}"
  rescue => e
    puts "[FAIL] #{domain} 解析失败: #{e.message}"
  end
end

puts "\n===== 3. /health 连通性检查（无需鉴权，验证域名+8080端口可达）====="
DOMAINS.each do |domain|
  begin
    uri  = URI("http://#{domain}:8080/health")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 5
    resp = http.get(uri.request_uri)
    puts "[OK]   #{domain}:8080/health -> HTTP #{resp.code}"
  rescue => e
    puts "[FAIL] #{domain}:8080/health 连接失败: #{e.message}"
  end
end

puts "\n===== 4. 鉴权签名验证（只读接口 /api/browser/locked）====="
DOMAINS.each do |domain|
  begin
    resp = RemoteApiClient.get("http://#{domain}:8080/api/browser/locked", open_timeout: 10, read_timeout: 10)
    case resp.code
    when '200'
      puts "[OK]   #{domain} /api/browser/locked -> HTTP 200（鉴权通过，返回: #{resp.body.to_s[0, 60]}）"
    when '401'
      puts "[FAIL] #{domain} /api/browser/locked -> HTTP 401（鉴权失败：密钥错/签名错/时间戳偏移/nonce重放）"
    else
      puts "[WARN] #{domain} /api/browser/locked -> HTTP #{resp.code}（非预期状态码）"
    end
  rescue => e
    puts "[FAIL] #{domain} 请求异常: #{e.message}"
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
domain_count = Browser.where(machine_ip: DOMAINS).count
puts "[INFO] 已迁移为域名的浏览器数: #{domain_count}"

puts "\n===== 完成 ====="
