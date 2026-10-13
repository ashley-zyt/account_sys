# postpeer 第三方发布平台 API 客户端。
#
# 封装 postpeer 的接口：创建 profile / 授权 URL / 查集成 / 发布 / 查结果。
# 鉴权：header `x-access-key: <api_key>`（区别于 postforme 的 Authorization Bearer）。
# 平台：postpeer 直接用 twitter/facebook/instagram/youtube/tiktok 等原值，无 x 映射。
#
# 配置（.env）：
#   POSTPEER_KEY=xxx        （必填，postpeer 平台的 API key）
#   POSTPEER_BASE_URL=xxx   （可选，默认 https://api.postpeer.dev）
#
# 所有方法统一返回 { code: HTTP状态码, body: 解析后的JSON, raw: 原始字符串 }，
# 业务成败判断交给调用方（code 2xx 才视为 HTTP 成功）。
module PostpeerApi
  require 'net/http'
  require 'uri'
  require 'json'

  BASE_URL = ENV['POSTPEER_BASE_URL'].presence || 'https://api.postpeer.dev'

  class << self
    # 创建 profile（授权前建立，用于按 profileId 隔离账号，授权后反查 accountId）
    # POST /v1/profiles
    def create_profile(name:)
      post('/v1/profiles', { name: name })
    end

    # 获取授权 OAuth URL（GET /v1/connect/{platform}）
    # @param platform [String] 平台名（facebook/instagram/youtube/tiktok）
    # @param profile_id [String, nil] 绑定 profile，便于授权后反查
    def connect_url(platform:, profile_id: nil)
      params = {}
      params[:profileId] = profile_id if profile_id.present?
      get("/v1/connect/#{platform}", params)
    end

    # 查询已连接的集成（GET /v1/connect/integrations）
    # @param profile_id [String, nil] 按 profile 过滤
    def integrations(profile_id: nil)
      params = {}
      params[:profileId] = profile_id if profile_id.present?
      get('/v1/connect/integrations', params)
    end

    # 创建发布任务（POST /v1/posts）
    # @param content [String] 标题/正文
    # @param platform [String] 平台名
    # @param account_id [String] postpeer 集成 ID（accountId）
    # @param media_urls [Array<String>] 媒体 URL（视频/图片）
    def create_post(content:, platform:, account_id:, media_urls: [])
      body = {
        content: content,
        platforms: [{ platform: platform, accountId: account_id }],
        publishNow: true
      }
      if media_urls.present?
        body[:mediaItems] = Array(media_urls).map { |url| { type: 'video', url: url } }
      end
      post('/v1/posts', body)
    end

    # 查询 post 状态（GET /v1/posts/{postId}）
    def post(post_id:)
      get("/v1/posts/#{post_id}")
    end

    # 判断响应是否成功：2xx 都算成功
    def success?(resp)
      resp[:code].to_i.between?(200, 299)
    end

    # 从集成列表响应里取 integrations 数组（GET /v1/connect/integrations → {integrations: [...]}）
    def integration_items(resp)
      body = resp[:body]
      body.is_a?(Hash) ? Array(body['integrations']) : Array(body)
    end

    private

    def get(path, params = {})
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(params) if params.any?
      perform(uri, Net::HTTP::Get.new(uri))
    end

    def post(path, body)
      uri = URI.join(BASE_URL, path)
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/json'
      req.body = body.to_json
      perform(uri, req)
    end

    def perform(uri, req)
      # API key 未配置时直接短路，避免发一个空 x-access-key 出去、收到含糊报错
      if api_key.blank?
        return { code: 401, body: {}, raw: 'POSTPEER_KEY 未配置（请在 .env 中设置，值来自 postpeer 官网的 API key）' }
      end

      req['x-access-key'] = api_key
      req['Accept'] = 'application/json'

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 30
      http.read_timeout = 60

      resp = http.request(req)
      parse_response(resp)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      { code: 0, body: {}, raw: "timeout: #{e.message}" }
    rescue => e
      { code: 0, body: {}, raw: e.message }
    end

    def parse_response(resp)
      raw = resp.body.to_s
      parsed = raw.present? ? JSON.parse(raw) : {}
      { code: resp.code.to_i, body: parsed, raw: raw }
    rescue JSON::ParserError
      { code: resp.code.to_i, body: {}, raw: raw }
    end

    def api_key
      ENV['POSTPEER_KEY'].to_s
    end
  end
end
