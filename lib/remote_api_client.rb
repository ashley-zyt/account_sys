# 运营机器 8080 端口接口的统一鉴权客户端
#
# 远端服务（运营机器 8080）对所有接口（/health 除外）强制要求 4 个请求头鉴权：
#   X-API-Key / X-Timestamp / X-Nonce / X-Signature（HMAC-SHA256）
# 本模块收敛签名逻辑，供全项目所有调用点复用，避免各处重复实现签名。
#
# 密钥配置：在 .env 中设置（dotenv-rails 自动加载）
#   REMOTE_API_KEY=xxx
#   REMOTE_API_SECRET=xxx
#
# 签名算法（与远端文档一致）：
#   bodyHash   = hex( sha256( 原始请求体字节 ) )              # 小写 hex
#   canonical  = METHOD + "\n" + PATH + "\n" + timestamp + "\n" + nonce + "\n" + bodyHash
#   signature  = hex( HMAC-SHA256( secret, canonical ) )
#
# 使用示例：
#   response = RemoteApiClient.post("http://<machine_ip>:8080/facebook/publish", { profile_name: "...", ... })
#   response.body  # 响应体字符串
module RemoteApiClient
  require 'openssl'
  require 'securerandom'
  require 'uri'
  require 'net/http'
  require 'json'

  class << self
    # 发送带鉴权的 POST 请求，返回 Net::HTTPResponse
    # @param url  [String] 完整 URL，如 http://<machine_ip>:8080/facebook/publish
    # @param body [Hash]   请求体（to_json 后发送，并基于同一 JSON 字符串计算 bodyHash）
    def post(url, body, open_timeout: 30, read_timeout: 600)
      uri = URI.parse(url)
      body_str = body.is_a?(String) ? body : body.to_json

      req = Net::HTTP::Post.new(uri.request_uri)
      req['Content-Type'] = 'application/json'
      req.body = body_str
      apply_auth!(req, uri, 'POST', body_str)

      perform(uri, req, open_timeout, read_timeout)
    end

    # 发送带鉴权的 GET 请求，返回 Net::HTTPResponse
    # GET 无请求体，bodyHash = hex(sha256(""))
    def get(url, open_timeout: 30, read_timeout: 100)
      uri = URI.parse(url)
      req = Net::HTTP::Get.new(uri.request_uri)
      apply_auth!(req, uri, 'GET', '')

      perform(uri, req, open_timeout, read_timeout)
    end

    private

    def perform(uri, req, open_timeout, read_timeout)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = open_timeout
      http.read_timeout = read_timeout
      http.request(req)
    end

    # 给请求加上 4 个鉴权头
    def apply_auth!(req, uri, method, body_str)
      timestamp = Time.now.to_i.to_s
      nonce     = SecureRandom.hex(16)                         # 32 位 hex
      body_hash = OpenSSL::Digest::SHA256.hexdigest(body_str)  # 小写 hex
      canonical = [method, uri.path, timestamp, nonce, body_hash].join("\n")
      signature = OpenSSL::HMAC.hexdigest('SHA256', api_secret, canonical)  # 小写 hex

      req['X-API-Key']   = api_key
      req['X-Timestamp'] = timestamp
      req['X-Nonce']     = nonce
      req['X-Signature'] = signature
    end

    def api_key
      ENV['REMOTE_API_KEY'].to_s
    end

    def api_secret
      ENV['REMOTE_API_SECRET'].to_s
    end
  end
end
