# 指纹浏览器代理信息同步器
#
# 调各运营机器的 GET /api/browser/profiles 获取所有 profile 的 name / proxy / cloud_id，
# 解析 proxy 字符串，按 profile_name 更新 browsers 表的代理信息与 cloud_id。
#
# proxy 示例：socks5://193.160.218.20:62185@ufa8RDTT:j5bNJK45
class BrowserProxySyncer
  PORT = 8080

  class << self
    # 遍历所有机器同步代理信息
    # @return [Hash] 同步统计
    def run
      stats = { machines: 0, profiles: 0, updated: 0, skipped: 0, failed: 0 }
      unmatched_samples = []

      Machine.find_each do |machine|
        next if machine.host.blank?
        stats[:machines] += 1
        r = sync_machine(machine)
        stats[:profiles] += r[:profiles]
        stats[:updated]  += r[:updated]
        stats[:skipped]  += r[:skipped]
        stats[:failed]   += r[:failed]
        unmatched_samples.concat(r[:unmatched_samples])
      end

      Rails.logger.info "[BrowserProxySyncer] 同步完成：#{stats.inspect}"
      Rails.logger.info "[BrowserProxySyncer] browsers 表 profile_name 示例(前20)：#{Browser.limit(20).pluck(:profile_name).inspect}"
      if unmatched_samples.any?
        Rails.logger.info "[BrowserProxySyncer] 未匹配示例(前20)：#{unmatched_samples.first(20).inspect}"
      end
      stats
    end

    # 同步单台机器的 profiles
    def sync_machine(machine)
      profiles = fetch_profiles(machine.host)
      result = { profiles: profiles.size, updated: 0, skipped: 0, failed: 0, unmatched_samples: [] }

      profiles.each do |p|
        name = p['name'].to_s.strip
        next if name.blank?

        browser = Browser.find_by(profile_name: name)

        if browser.nil?
          result[:skipped] += 1
          result[:unmatched_samples] << name if result[:unmatched_samples].size < 20
          next
        end

        attrs = parse_proxy(p['proxy'].to_s.strip)
        next if attrs.nil?

        browser.update(attrs) ? result[:updated] += 1 : result[:failed] += 1
      end
      result
    rescue => e
      Rails.logger.error "[BrowserProxySyncer] 机器 #{machine.host} 同步异常: #{e.message}"
      { profiles: 0, updated: 0, skipped: 0, failed: 1, unmatched_samples: [] }
    end

    # 拉取机器 profiles 列表
    def fetch_profiles(host)
      resp = RemoteApiClient.get("http://#{host}:#{PORT}/api/browser/profiles", open_timeout: 60, read_timeout: 60)
      body = JSON.parse(resp.body)
      data = body.is_a?(Hash) ? body['data'] : body
      Array(data)
    rescue => e
      Rails.logger.error "[BrowserProxySyncer] 获取 #{host} profiles 失败: #{e.message}"
      []
    end

    # 解析 proxy 字符串 → { proxy_type:, proxy_host:, proxy_port:, proxy_username:, proxy_password: }
    # 支持带认证 socks5://host:port@user:pass 与无认证 socks5://host:port 两种
    def parse_proxy(proxy)
      return nil if proxy.blank?
      if (m = proxy.match(%r{\A([a-z0-9]+)://([^:/@]+):(\d+)@([^:@]+):([^@]+)\z}))
        { proxy_type: m[1], proxy_host: m[2], proxy_port: m[3].to_i, proxy_username: m[4], proxy_password: m[5] }
      elsif (m = proxy.match(%r{\A([a-z0-9]+)://([^:/@]+):(\d+)\z}))
        { proxy_type: m[1], proxy_host: m[2], proxy_port: m[3].to_i, proxy_username: nil, proxy_password: nil }
      end
    end
  end
end
