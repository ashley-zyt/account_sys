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

      request = Net::HTTP::Post.new(uri.path, "Content-Type" => "application/json")
      request.body = { username: AUTH_USERNAME, password: AUTH_PASSWORD }.to_json

      response = http.request(request)
      return nil unless response.code == "200"

      data = JSON.parse(response.body)
      data.dig("data", "token")
    rescue => e
      Rails.logger.error "[RedNoteApi] 获取 Token 失败: #{e.message}"
      nil
    end

    # 创建采集任务
    # keyword 参数为 RedNoteKeyword 实例
    def create_task(keyword)
      token = fetch_token
      return false unless token

      uri = URI("#{BASE_URL}/tasks")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Post.new(uri.path,
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{token}"
      )
      request.body = {
        keyword: keyword.keyword,
        keyword_code: keyword.keyword_code,
        theme: keyword.theme
      }.to_json

      response = http.request(request)
      return false unless response.code == "200" || response.code == "201"

      data = JSON.parse(response.body)
      task_id = data.dig("data", "task_id") || data.dig("data", "id")
      keyword.update(task_id: task_id, status: 1) if task_id # 待执行
      true
    rescue => e
      Rails.logger.error "[RedNoteApi] 创建任务失败 (keyword_code=#{keyword.keyword_code}): #{e.message}"
      false
    end

    # 同步单个关键词的任务状态
    def sync_task_status(keyword)
      return unless keyword.task_id.present?
      return if keyword.status == 3 # 已完成的不再同步

      token = fetch_token
      return false unless token

      uri = URI("#{BASE_URL}/tasks?keyword_code=#{URI.encode_www_form_component(keyword.keyword_code)}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 10

      request = Net::HTTP::Get.new(uri.request_uri,
        "Authorization" => "Bearer #{token}"
      )

      response = http.request(request)
      return false unless response.code == "200"

      data = JSON.parse(response.body)
      task_data = data.is_a?(Array) ? data.first : data.dig("data")

      return unless task_data.present?

      # 映射远程状态到本地状态
      remote_status = task_data["status"] || task_data["state"]
      local_status = map_remote_status(remote_status)
      keyword.update(
        status: local_status,
        result_data: task_data.to_json,
        task_id: task_data["id"] || task_data["task_id"] || keyword.task_id
      )
      true
    rescue => e
      Rails.logger.error "[RedNoteApi] 同步任务状态失败 (keyword_code=#{keyword.keyword_code}): #{e.message}"
      false
    end

    # 批量同步所有待执行和执行中的关键词
    def sync_all_pending
      keywords = RedNoteKeyword.where(status: [1, 2]) # 待执行、执行中
      keywords.each { |kw| sync_task_status(kw) }
    end

    private

    # 将远程 API 返回的状态映射到本地状态码
    def map_remote_status(remote_status)
      case remote_status.to_s.downcase
      when "pending", "waiting", "queued"
        1 # 待执行
      when "running", "processing", "executing"
        2 # 执行中
      when "completed", "success", "done", "finished"
        3 # 执行完成
      when "failed", "error"
        4 # 任务失败
      else
        1 # 未知状态默认为待执行
      end
    end
  end
end
