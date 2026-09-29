# X（Twitter）API 客户端 —— OAuth 2.0 认证与 token 管理。
#
# 封装 X API v2 的 OAuth 2.0 Authorization Code + PKCE 流程：
#   1. 生成 PKCE（code_verifier + code_challenge）
#   2. 构造授权 URL（redirect_uri 指向 localhost，机器端检测跳转截 code）
#   3. 用 code 换 access_token + refresh_token
#   4. 用 refresh_token 刷新 access_token
#
# 配置（.env）：
#   X_CLIENT_ID=xxx           （X Developer Portal 的 OAuth 2.0 Client ID）
#   X_CLIENT_SECRET=xxx       （OAuth 2.0 Client Secret）
#   X_REDIRECT_URI=xxx        （可选，默认 http://127.0.0.1:9000/callback）
#
# 所有方法统一返回 { code: HTTP状态码, body: 解析后的JSON, raw: 原始字符串 }，
# 业务成败判断交给调用方（2xx 视为成功）。
module XApi
  require 'net/http'
  require 'uri'
  require 'json'
  require 'securerandom'
  require 'digest'
  require 'base64'

  # 授权端点 / token 端点
  AUTHORIZE_ENDPOINT = 'https://twitter.com/i/oauth2/authorize'
  TOKEN_ENDPOINT = 'https://api.twitter.com/2/oauth2/token'
  # X API v2 通用 base（DM / users 等资源接口）
  API_BASE = 'https://api.twitter.com'

  # 授权范围：私信 + 评论 + 读用户 + 离线访问（offline.access 才会返回 refresh_token）
  SCOPE = 'dm.read dm.write tweet.read tweet.write users.read offline.access'

  class << self
    # 生成 PKCE 的 code_verifier + code_challenge（S256）。
    # @return [Array<String, String>] [code_verifier, code_challenge]
    def generate_pkce
      verifier = SecureRandom.urlsafe_base64(64).gsub(/=+\z/, '')
      challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
      [verifier, challenge]
    end

    # 构造 OAuth 2.0 授权 URL。
    # @param state [String] 防 CSRF 随机串
    # @param code_challenge [String] PKCE code_challenge
    # @return [String] 授权 URL
    def authorization_url(state:, code_challenge:)
      params = {
        response_type: 'code',
        client_id: client_id,
        redirect_uri: redirect_uri,
        scope: SCOPE,
        state: state,
        code_challenge: code_challenge,
        code_challenge_method: 'S256'
      }
      "#{AUTHORIZE_ENDPOINT}?#{params.to_query}"
    end

    # 用授权码换 access_token + refresh_token（grant_type=authorization_code）。
    # @return [Hash] { code:, body:, raw: }
    def exchange_code(code:, code_verifier:)
      post_token(
        code: code,
        grant_type: 'authorization_code',
        client_id: client_id,
        redirect_uri: redirect_uri,
        code_verifier: code_verifier
      )
    end

    # 用 refresh_token 刷新 access_token（grant_type=refresh_token）。
    # @return [Hash] { code:, body:, raw: }
    def refresh(refresh_token:)
      post_token(
        refresh_token: refresh_token,
        grant_type: 'refresh_token',
        client_id: client_id
      )
    end

    # 读取当前认证用户信息（GET /2/users/me），拿 x_user_id。
    # @return [Hash] { code:, body:, raw: }，body['data']['id'] 即 X 平台 user id
    def me(access_token:)
      uri = URI('https://api.twitter.com/2/users/me')
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{access_token}"
      req['Accept'] = 'application/json'
      perform(uri, req)
    end

    # 按用户名查用户（GET /2/users/by/username/:username），拿 user_id。
    # @return [Hash] { code:, body:, raw: }，body['data']['id'] 即对方 X user id
    def user_by_username(access_token:, username:)
      u = username.to_s.sub(/\A@/, '').strip
      return { code: 0, body: {}, raw: 'username 为空' } if u.blank?

      uri = URI("#{API_BASE}/2/users/by/username/#{URI.encode_www_form_component(u)}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{access_token}"
      req['Accept'] = 'application/json'
      perform(uri, req)
    end

    # 发私信（POST /2/dm_conversations/with/:participant_id/messages），
    # 自动创建/复用 1-1 会话。body 的 text 是对象 { text: "..." }。
    # @return [Hash] { code:, body:, raw: }
    def send_dm(access_token:, participant_id:, text:)
      uri = URI("#{API_BASE}/2/dm_conversations/with/#{participant_id}/messages")
      req = Net::HTTP::Post.new(uri)
      req['Authorization'] = "Bearer #{access_token}"
      req['Content-Type'] = 'application/json'
      req['Accept'] = 'application/json'
      req.body = { text: { text: text } }.to_json
      perform(uri, req)
    end

    # 拉取 1-1 会话的 DM 事件（GET /2/dm_conversations/with/:participant_id/dm_events）。
    # 需显式带 dm_event.fields 才有 sender_id / created_at（默认只返回 id/text/event_type）。
    # @return [Hash] { code:, body:, raw: }，body['data'] 为事件数组，body.dig('meta','next_token') 分页游标
    def dm_events(access_token:, participant_id:, max_results: 100, pagination_token: nil)
      params = {
        max_results: max_results,
        'dm_event.fields' => 'id,text,event_type,dm_conversation_id,created_at,sender_id'
      }
      params[:pagination_token] = pagination_token if pagination_token.present?
      uri = URI("#{API_BASE}/2/dm_conversations/with/#{participant_id}/dm_events?#{URI.encode_www_form(params)}")
      req = Net::HTTP::Get.new(uri)
      req['Authorization'] = "Bearer #{access_token}"
      req['Accept'] = 'application/json'
      perform(uri, req)
    end

    # 判断响应是否成功：2xx 都算成功
    def success?(resp)
      resp[:code].to_i.between?(200, 299)
    end

    # 校验配置是否齐全
    def configured?
      client_id.present? && client_secret.present? && redirect_uri.present?
    end

    private

    def client_id
      ENV['X_CLIENT_ID'].to_s
    end

    def client_secret
      ENV['X_CLIENT_SECRET'].to_s
    end

    def redirect_uri
      # 必须用机器端对外 HTTPS 域名（X 拒绝 localhost/127.0.0.1 这类 loopback 回调，
      # 且 Web App / Automated App 类型要求 https）。机器端会自动从授权 URL 的
      # redirect_uri 参数解析检测前缀，无需机器端改代码。
      ENV['X_REDIRECT_URI'].presence || 'http://127.0.0.1:9000/callback'
    end

    # POST token 端点（Basic Auth + application/x-www-form-urlencoded）
    def post_token(body)
      return { code: 401, body: {}, raw: 'X_CLIENT_ID / X_CLIENT_SECRET 未配置（请在 .env 中设置）' } unless client_id.present? && client_secret.present?

      uri = URI(TOKEN_ENDPOINT)
      req = Net::HTTP::Post.new(uri)
      req['Content-Type'] = 'application/x-www-form-urlencoded'
      req['Accept'] = 'application/json'
      req.basic_auth(client_id, client_secret)
      req.body = URI.encode_www_form(body)

      perform(uri, req)
    end

    def perform(uri, req)
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
  end
end
