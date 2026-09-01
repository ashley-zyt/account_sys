# 花生视频 → 抖音 / 视频号 自动发布任务
#
# 触发方式：每天下午 16:00 由 whenever 定时执行（见 config/schedule.rb）
# 手动执行：bundle exec rails runner 'DySphHuashengPublishWorker.run'
#
# 数据源：HuashengTask（status=pending 且 theme=花生视频-抖音号视频号 且 platform=抖音-视频号）
#   取一条任务，同时发布到抖音（/douyin/publish）和视频号（/weixin/publish）：
#   - profile_name  固定 douyin01
#   - text          用 task.title（已含话题标签，如 #快时尚 #Shein）
#   - video_oss_url 用 task.oss_url（已签名的 URL）
# 全部平台成功 → 任务 status=success；任一失败 → status=failed（error_msg 记录各平台结果）
# 结束后通过钉钉机器人（agic_dw）通知结果
class DySphHuashengPublishWorker
  # 要发布的主题
  THEME = "花生视频-抖音号视频号"

  # 任务表的 platform 值（抖音+视频号 合并任务）
  PLATFORM = "抖音-视频号"

  # 发布接口主机（抖音/视频号共用）
  PUBLISH_HOST = "ag15.juzhiic.com"

  # 固定 profile_name
  PROFILE_NAME = "douyin01"

  # 发布目标：平台名 → 发布端点（顺序即通知里的展示顺序）
  TARGETS = {
    "抖音" => "/douyin/publish",
    "视频号" => "/weixin/publish"
  }.freeze

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

      task = fetch_task
      if task.nil?
        Rails.logger.info "[DySphHuashengPublishWorker] 无待发布任务（theme=#{THEME} platform=#{PLATFORM}）"
        notify_empty
        return
      end
      Rails.logger.info "[DySphHuashengPublishWorker] 取到任务 id=#{task.id} keyword=#{task.keyword} title=#{task.title}"

      # 依次发布抖音、视频号
      results = {}
      TARGETS.each do |platform_name, endpoint|
        results[platform_name] = publish(task, endpoint, platform_name)
        Rails.logger.info "[DySphHuashengPublishWorker] #{platform_name} 发布结果: #{results[platform_name].inspect}"
      end

      # 更新任务状态
      update_task_status(task, results)

      # 钉钉通知
      notify_result(task, results)

      Rails.logger.info "[DySphHuashengPublishWorker] ===== done ====="
    end

    # 取一条待发布任务（抖音+视频号合并任务）
    def fetch_task
      HuashengTask.where(status: :pending, theme: THEME, platform: PLATFORM).order(:id).first
    end

    # 发布到指定端点
    # @return [Hash] { success: true/false, message: "结果说明" }
    def publish(task, endpoint, platform_name)
      body = {
        profile_name:  PROFILE_NAME,
        text:          task.title.to_s,
        video_oss_url: task.oss_url.to_s
      }
      Rails.logger.info "[DySphHuashengPublishWorker] [#{platform_name}] 请求 #{endpoint} body=#{body.to_json}"

      response = http_post_json("https://#{PUBLISH_HOST}#{endpoint}", body)

      if response.is_a?(Hash) && response["type"] == "success"
        { success: true, message: "成功" }
      else
        { success: false, message: extract_error(response) }
      end
    end

    # 发布结束后更新任务状态：全部平台成功 → success，任一失败 → failed
    # 注：这类抖音-视频号任务不走账号分配，account_id 恒为空；
    #     而 model 有「非 pending 必须有账号」的校验，故用 save(validate: false) 绕过
    def update_task_status(task, results)
      all_success = results.values.all? { |r| r[:success] }

      if all_success
        task.status = :success
        task.actual_publish_time = Time.current
        task.error_msg = nil
      else
        task.status = :failed
        task.error_msg = results.map { |k, r| "#{k}:#{r[:success] ? "成功" : "失败(#{r[:message]})"}" }.join("；")
      end
      task.save(validate: false)

      Rails.logger.info "[DySphHuashengPublishWorker] 任务 id=#{task.id} 状态已更新为 #{all_success ? "success" : "failed"}"
    end

    # POST JSON，返回解析后的响应；异常统一转成 { type: "error", error_info: ... }
    def http_post_json(endpoint, body)
      response = RemoteApiClient.post(endpoint, body, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
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
    # keyword 取任务 keyword 字段第一段（去掉 |Chinese|9:16 之类的生成参数）
    def notify_result(task, results)
      keyword = task.keyword.to_s.split("|").first.to_s.strip
      keyword = task.keyword.to_s if keyword.empty?

      douyin_text    = platform_result_text(results["抖音"])
      shipinhao_text = platform_result_text(results["视频号"])

      content = "#{keyword}:抖音:#{douyin_text}；视频号:#{shipinhao_text}；"
      Dingtalk.send_text(NOTIFY_ROBOT, content)
    end

    # 无待发布数据时的通知
    def notify_empty
      Dingtalk.send_text(NOTIFY_ROBOT, "今日无待发布的 #{THEME} 数据")
    end

    private

    def platform_result_text(result)
      result[:success] ? "成功" : "失败(#{result[:message]})"
    end

    def setup_logger
      logger = ActiveSupport::Logger.new(File.join(Rails.root, LOG_FILE))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
