require "net/http"
require "uri"
require "json"

# RedNote (小红书) 远程 API 服务
# 负责 JWT 认证、创建采集任务、同步任务状态
class RedNoteApiService
  BASE_URL = "http://47.251.29.190:8080/api/v1"
  AUTH_USERNAME = "admin451134"
  AUTH_PASSWORD = "$35@1243ssed"

  class << self
    # 获取 JWT Token
    def fetch_token
      uri = URI("#{BASE_URL}/auth/login")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json; charset=utf-8")
      body = { username: AUTH_USERNAME, password: AUTH_PASSWORD }.to_json
      Rails.logger.info "[RedNoteApi] 登录响应 code=#{response.code} body=#{response.body.truncate(200)}"
      request.body = body.dup.force_encoding("ASCII-8BIT")

      response = http.request(request)
      Rails.logger.info "[RedNoteApi] 登录响应 code=#{response.code} body=#{response.body.truncate(200)}"

      return nil unless response.code == "200"

      data = JSON.parse(response.body)
      token = data.dig("data", "token")
      Rails.logger.info "[RedNoteApi] 获取 Token #{token ? '成功' : '失败：响应中无 token'}"
      token
    rescue => e
      Rails.logger.error "[RedNoteApi] 获取 Token 异常: #{e.message}"
      nil
    end

    # 创建采集任务
    # POST /api/v1/tasks
    #   keyword_code      (必填) 关键词编码
    #   search_phrase     (必填) 搜索短语
    #   content_type      图文 / 视频 / '' (不限)
    #   search_max_results 搜索前N条 (优先级高于全局设置)
    #   top_n_by_likes     按点赞取前N条下载 (优先级高于全局设置)
    def create_task(keyword)
      token = fetch_token
      unless token
        Rails.logger.error "[RedNoteApi] 创建任务失败: 无 Token (keyword_code=#{keyword.keyword_code})"
        return false
      end

      body_hash = {
        keyword_code: keyword.keyword_code,
        search_phrase: keyword.keyword,
        content_type: "图文",
        search_max_results: RedNoteSetting.current.search_max_results,
        top_n_by_likes: RedNoteSetting.current.top_n_by_likes
      }

      uri = URI("#{BASE_URL}/tasks")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Post.new(uri.path,
        "Content-Type" => "application/json; charset=utf-8",
        "Authorization" => "Bearer #{token}"
      )
      request.body = body_hash.to_json.dup.force_encoding("ASCII-8BIT")

      Rails.logger.info "[RedNoteApi] 发送创建任务请求: #{request.body}"

      response = http.request(request)
      Rails.logger.info "[RedNoteApi] 创建任务响应 code=#{response.code} body=#{response.body.truncate(500)}"

      unless response.code == "200" || response.code == "201"
        Rails.logger.error "[RedNoteApi] 创建任务失败: HTTP #{response.code} body=#{response.body}"
        return false
      end

      data = JSON.parse(response.body)
      task_id = data.dig("data", "task_id") || data.dig("data", "id")

      unless task_id
        Rails.logger.error "[RedNoteApi] 创建任务失败: 响应中无 task_id, data=#{data.inspect}"
        return false
      end

      keyword.update(task_id: task_id, status: 1)
      Rails.logger.info "[RedNoteApi] 创建任务成功: keyword_code=#{keyword.keyword_code} task_id=#{task_id}"
      true
    rescue => e
      Rails.logger.error "[RedNoteApi] 创建任务异常 (keyword_code=#{keyword.keyword_code}): #{e.message}"
      false
    end

    # 同步单个关键词的任务状态
    def sync_task_status(keyword)
      return unless keyword.task_id.present?
      return if keyword.status == 3

      token = fetch_token
      unless token
        Rails.logger.error "[RedNoteApi] 同步状态失败: 无 Token"
        return false
      end

      uri = URI("#{BASE_URL}/tasks?keyword_code=#{URI.encode_www_form_component(keyword.keyword_code)}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 30

      request = Net::HTTP::Get.new(uri.request_uri,
        "Authorization" => "Bearer #{token}"
      )

      response = http.request(request)
      Rails.logger.info "[RedNoteApi] 同步状态响应 code=#{response.code} keyword_code=#{keyword.keyword_code}"

      return false unless response.code == "200"

      data = JSON.parse(response.body)
      task_data = data.is_a?(Array) ? data.first : data.dig("data")

      return unless task_data.present?

      remote_status = task_data["status"] || task_data["state"]
      local_status = map_remote_status(remote_status)
      keyword.update(
        status: local_status,
        result_data: task_data.to_json,
        task_id: task_data["id"] || task_data["task_id"] || keyword.task_id
      )
      true
    rescue => e
      Rails.logger.error "[RedNoteApi] 同步状态异常 (keyword_code=#{keyword.keyword_code}): #{e.message}"
      false
    end

    # 批量同步所有待执行和执行中的关键词
    def sync_all_pending
      keywords = RedNoteKeyword.where(status: [1, 2])
      keywords.each { |kw| sync_task_status(kw) }
    end

    private

    def map_remote_status(remote_status)
      case remote_status.to_s.downcase
      when "pending", "waiting", "queued"
        1
      when "running", "processing", "executing"
        2
      when "completed", "success", "done", "finished"
        3
      when "failed", "error"
        4
      else
        1
      end
    end
  end
end
