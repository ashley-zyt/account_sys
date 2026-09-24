# postforme 第三方发布平台 API 客户端。
#
# 封装 postforme 的 4 个接口：授权 URL / 查账号 / 发布 / 查结果。
# 鉴权：Bearer token（JWT），header `Authorization: Bearer <api_key>`。
# 平台映射：本系统用 twitter，postforme 用 x，调用前统一映射。
#
# 配置（.env）：
#   POSTFORME_API_KEY=xxx        （必填，postforme 平台的 API key）
#   POSTFORME_BASE_URL=xxx       （可选，默认 https://api.postforme.dev）
#
# 所有方法统一返回 { code: HTTP状态码, body: 解析后的JSON, raw: 原始字符串 }，
# 业务成败判断交给调用方（code 2xx 才视为 HTTP 成功）。
module PostformeApi
  require 'net/http'
  require 'uri'
  require 'json'

  BASE_URL = ENV['POSTFORME_BASE_URL'].presence || 'https://api.postforme.dev'

  # 平台名映射：本系统 → postforme（twitter 在 postforme 叫 x）
  PLATFORM_MAP = {
    'facebook'  => 'facebook',
    'twitter'   => 'x',
    'tiktok'    => 'tiktok',
    'youtube'   => 'youtube',
    'instagram' => 'instagram'
  }.freeze

  class << self
    # 获取授权 URL（POST /v1/social-accounts/auth-url）
    # @param platform [String] 本系统平台名（facebook/twitter/...）
    # @param external_id [String, nil] 本系统账号 ID（用于授权后反查）
    def auth_url(platform:, external_id: nil)
      body = { platform: map_platform(platform) }
      body[:external_id] = external_id if external_id.present?
      post('/v1/social-accounts/auth-url', body)
    end

    # 查询社交账号列表（GET /v1/social-accounts）
    # @param external_id [String, nil] 按本系统账号 ID 反查（授权后拿 social_account_id）
    # @param platform [String, nil] 按平台过滤
    def social_accounts(external_id: nil, platform: nil)
      params = {}
      params[:external_id] = external_id if external_id.present?
      params[:platform] = map_platform(platform) if platform.present?
      get('/v1/social-accounts', params)
    end

    # 创建发布任务（POST /v1/social-posts）
    # @param caption [String] 标题/正文
    # @param social_account_ids [Array<String>] postforme 社交账号 ID 数组
    # @param media_urls [Array<String>] 媒体 URL 数组（图片/视频公开链接）
    # @param external_id [String, nil] 本系统任务标识（用于关联）
    # @param scheduled_at [String, nil] 定时发布时间（ISO8601）
    def create_post(caption:, social_account_ids:, media_urls: [], external_id: nil, scheduled_at: nil)
      body = {
        caption: caption,
        social_accounts: Array(social_account_ids)
      }
      body[:media] = Array(media_urls).map { |url| { url: url } } if media_urls.present?
      body[:external_id] = external_id if external_id.present?
      body[:scheduled_at] = scheduled_at if scheduled_at.present?
      post('/v1/social-posts', body)
    end

    # 查询 post 发布结果（GET /v1/social-post-results?post_id=xxx）
    # 返回 SocialPostResultDto：success(boolean)/error/platform_data{url}
    def post_result(post_id:)
      get('/v1/social-post-results', { post_id: post_id })
    end

    # 查询 post 详情（GET /v1/social-posts/{id}）
    # 返回 SocialPostDto：status(draft/scheduled/processing/processed)
    def post(post_id:)
      get("/v1/social-posts/#{post_id}")
    end

    # 判断响应是否成功：2xx 都算成功（postforme 部分接口返回 201 而非 200，如 auth-url）
    def success?(resp)
      resp[:code].to_i.between?(200, 299)
    end

    # 从分页响应里取 data 数组（postforme 列表接口统一返回 {data: [...], meta: {...}}）
    def items(resp)
      body = resp[:body]
      body.is_a?(Hash) ? Array(body['data']) : Array(body)
    end

    private

    # 平台名映射（twitter → x），未知平台原样返回
    def map_platform(platform)
      PLATFORM_MAP.fetch(platform.to_s, platform.to_s)
    end

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
      # API key 未配置时直接短路，避免发一个空 Bearer 出去、收到含糊的 missing_credentials
      if api_key.blank?
        return { code: 401, body: {}, raw: 'POSTFORME_API_KEY 未配置（请在 .env 中设置，值来自 postforme 官网的 API key）' }
      end

      req['Authorization'] = "Bearer #{api_key}"
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
      ENV['POSTFORME_API_KEY'].to_s
    end
  end
end
