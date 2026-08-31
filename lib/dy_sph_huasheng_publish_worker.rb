# 花生视频 → 抖音 / 视频号 自动发布任务
#
# 触发方式：每天下午 16:00 由 whenever 定时执行（见 config/schedule.rb）
# 手动执行：bundle exec rails runner 'DySphHuashengPublishWorker.run'
#
# 流程：
#   1. 获取一条「执行完成」的花生关键词（与 /api/v1/huasheng/completed_keywords 查询逻辑一致）
#   2. 依次发布到抖音、视频号
#   3. 发布结束后通过钉钉机器人（agic_dw）通知结果
class DySphHuashengPublishWorker
  # 要发布的主题（对应 completed_keywords 接口的 theme 参数）
  THEME = "花生视频-抖音号视频号"

  # 发布接口主机（抖音/视频号共用）
  PUBLISH_HOST = "174.139.46.15:8080"

  # 固定 profile_name
  PROFILE_NAME = "douyin01"

  # 平台 → 发布端点
  PUBLISH_ENDPOINTS = {
    "douyin"    => "/douyin/publish",
    "shipinhao" => "/weixin/publish"
  }.freeze

  # 发布平台（顺序即发布顺序）
  PLATFORMS = PUBLISH_ENDPOINTS.keys

  # 钉钉机器人（agic_dw 已在 config/dingtalk.yml 配置）
  NOTIFY_ROBOT = :agic_dw

  # HTTP 超时（秒）
  OPEN_TIMEOUT = 30
  READ_TIMEOUT = 600

  # 日志文件
  LOG_FILE = "log/dy_sph_huasheng_publish_worker.log"

  class << self
    def run
      setup_logger
      Rails.logger.info "[DySphHuashengPublishWorker] ===== start ====="

      # 1. 获取一条待发布数据
      payload = fetch_one
      unless payload
        Rails.logger.info "[DySphHuashengPublishWorker] 无待发布数据（theme=#{THEME}，status=执行完成）"
        notify_empty
        return
      end

      # 先打印取到的数据，便于核对 text / video_url 是否正确
      Rails.logger.info "[DySphHuashengPublishWorker] 取到数据："
      Rails.logger.info "  keyword_id: #{payload[:keyword_id]}"
      Rails.logger.info "  keyword:    #{payload[:keyword]}"
      Rails.logger.info "  theme:      #{payload[:theme]}"
      Rails.logger.info "  video_url:  #{payload[:video_url]}"
      Rails.logger.info "  text:       #{payload[:text]}"

      # 2. 逐平台发布（暂注释：先核对上面生成的数据是否正确，确认无误后再放开）
      # results = {}
      # PLATFORMS.each do |platform|
      #   results[platform] = publish(platform, payload)
      #   Rails.logger.info "[DySphHuashengPublishWorker] #{platform} 发布结果: #{results[platform].inspect}"
      # end

      # 3. 钉钉通知（暂注释，随发布一起放开）
      # notify_result(payload, results)

      Rails.logger.info "[DySphHuashengPublishWorker] ===== done ====="
    end

    # 获取一条待发布数据（含视频 URL、text）
    # TODO: 若要「每天只发一条新数据、不重复发布」，需给 HuashengKeyword 增加
    #       「已发布」标记字段（如 published_at），此处改为 .where(published_at: nil)
    def fetch_one
      keyword = HuashengKeyword.where(theme: THEME, status: 3).order(:id).first
      keyword ? build_payload(keyword) : nil
    end

    # 从 HuashengKeyword 组装发布所需字段（与 completed_keywords 接口解析逻辑一致）
    def build_payload(keyword)
      result     = (JSON.parse(keyword.result_data) rescue {})
      object_key = result["oss_url"].to_s.strip.gsub(/^`|`$/, "").strip
      script     = result["Script"].is_a?(Hash) ? result["Script"] : (result["script"].is_a?(Hash) ? result["script"] : {})

      {
        keyword_id: keyword.id,
        keyword:    keyword.keyword,
        theme:      keyword.theme,
        video_url:  HuashengTask.oss_v1_sign_url(object_key),
        text:       build_text(script)
      }
    end

    # text = title + tags，如 "Shein席卷欧美，快时尚的狂欢与代价 #快时尚 #Shein #消费反思"
    def build_text(script)
      title = script["title"].to_s.strip
      tags  = normalize_tags(script["tags"])
      [title, tags].reject(&:empty?).join(" ")
    end

    # tags 可能是数组（自动补 # 前缀）或已拼好的字符串
    def normalize_tags(tags)
      case tags
      when Array
        tags.map { |t| t.to_s.strip }
            .reject(&:empty?)
            .map { |t| t.start_with?("#") ? t : "##{t}" }
            .join(" ")
      when String
        tags.strip
      else
        ""
      end
    end

    # 发布到指定平台
    # @param platform [String] "douyin" / "shipinhao"
    # @return [Hash] { success: true/false, message: "结果说明" }
    def publish(platform, payload)
      endpoint = "http://#{PUBLISH_HOST}#{PUBLISH_ENDPOINTS.fetch(platform)}"
      body = {
        profile_name:  PROFILE_NAME,
        text:          payload[:text],
        video_oss_url: payload[:video_url]
      }
      Rails.logger.info "[DySphHuashengPublishWorker] 请求 #{platform}: #{endpoint} body=#{body.to_json}"

      response = http_post_json(endpoint, body)

      if response.is_a?(Hash) && response["type"] == "success"
        { success: true, message: "发布成功" }
      else
        { success: false, message: extract_error(response) }
      end
    end

    # POST JSON，返回解析后的响应；异常统一转成 { type: "error", error_info: ... }
    def http_post_json(endpoint, body)
      require 'net/http'
      require 'json'

      uri  = URI.parse(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request.body = body.to_json

      response = http.request(request)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      { "type" => "error", "error_info" => "响应非JSON: #{e.message}" }
    rescue => e
      { "type" => "error", "error_info" => "请求异常: #{e.class} #{e.message}" }
    end

    # 提取失败原因（优先 error_info/error/message，否则整个响应原文）
    def extract_error(response)
      return response.to_s unless response.is_a?(Hash)
      response["error_info"] || response["error"] || response["message"] || response.to_json
    end

    # 钉钉通知：[keyword]:抖音:成功/失败(错误原因)；视频号:成功/失败(错误原因)；
    def notify_result(payload, results)
      content = "#{payload[:keyword]}:抖音:#{platform_result_text(results["douyin"])}；视频号:#{platform_result_text(results["shipinhao"])}；"
      Dingtalk.send_text(NOTIFY_ROBOT, content)
    end

    # 无待发布数据时的通知（可选，按需启用）
    def notify_empty
      # Dingtalk.send_text(NOTIFY_ROBOT, "今日无待发布的 #{THEME} 数据")
    end

    private

    def platform_result_text(result)
      return "未执行" unless result
      result[:success] ? "成功" : "失败(#{result[:message]})"
    end

    def setup_logger
      logger = ActiveSupport::Logger.new(File.join(Rails.root, LOG_FILE))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
