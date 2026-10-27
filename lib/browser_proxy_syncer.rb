# 指纹浏览器代理信息同步器
#
# 反过来查询：先取系统里「状态正常」的浏览器，拿它们的 profile_name 去各机器
# GET /api/browser/profiles 返回的内容里比对，命中后解析 proxy 更新代理信息。
#
# proxy 示例：socks5://193.160.218.20:62185@ufa8RDTT:j5bNJK45
class BrowserProxySyncer
  PORT = 8080

  class << self
    # 同步所有状态正常浏览器的代理信息
    # @return [Hash] 同步统计
    def run
      stats = { profiles_fetched: 0, browsers: 0, updated: 0, unmatched: 0, failed: 0 }
      unmatched_samples = []

      # 1. 合并所有机器的 profiles，建成 name → profile 映射
      profiles_by_name = {}
      Machine.find_each do |machine|
        next if machine.host.blank?
        fetch_profiles(machine.host).each do |p|
          name = p['name'].to_s.strip
          profiles_by_name[name] = p if name.present?
        end
      end
      stats[:profiles_fetched] = profiles_by_name.size

      # 2. 遍历状态正常的浏览器，用 profile_name 去比对
      browsers = Browser.where(status: 0)
      stats[:browsers] = browsers.size

      browsers.each do |browser|
        name = browser.profile_name.to_s.strip
        p = profiles_by_name[name]
        if p.nil?
          stats[:unmatched] += 1
          unmatched_samples << name if unmatched_samples.size < 20
          next
        end

        attrs = parse_proxy(p['proxy'].to_s.strip)
        if attrs.nil?
          stats[:failed] += 1
          next
        end

        browser.update(attrs) ? stats[:updated] += 1 : stats[:failed] += 1
      end

      Rails.logger.info "[BrowserProxySyncer] 同步完成：#{stats.inspect}"
      if unmatched_samples.any?
        Rails.logger.info "[BrowserProxySyncer] 未匹配示例(前20)：#{unmatched_samples.inspect}"
      end
      stats
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
    # 支持三种格式：
    #   带认证 @ 分隔：socks5://host:port@user:pass
    #   带认证 : 分隔：socks5://host:port:user:pass
    #   无认证：      socks5://host:port
    def parse_proxy(proxy)
      return nil if proxy.blank?
      if (m = proxy.match(%r{\A([a-z0-9]+)://([^:/@]+):(\d+)@([^:@]+):([^@]+)\z}))
        { proxy_type: m[1], proxy_host: m[2], proxy_port: m[3].to_i, proxy_username: m[4], proxy_password: m[5] }
      elsif (m = proxy.match(%r{\A([a-z0-9]+)://([^:/@]+):(\d+):([^:@]+):([^:@]+)\z}))
        { proxy_type: m[1], proxy_host: m[2], proxy_port: m[3].to_i, proxy_username: m[4], proxy_password: m[5] }
      elsif (m = proxy.match(%r{\A([a-z0-9]+)://([^:/@]+):(\d+)\z}))
        { proxy_type: m[1], proxy_host: m[2], proxy_port: m[3].to_i, proxy_username: nil, proxy_password: nil }
      end
    end
  end
end
