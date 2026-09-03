# 花生视频 → 抖音 / 视频号 自动发布任务
#
# 触发方式：每天下午 16:00 由 whenever 定时执行（见 config/schedule.rb）
# 手动执行：bundle exec rails runner 'DySphHuashengPublishWorker.run'
#
# 数据源：HuashengTask（status=pending 且 theme=花生视频-抖音号视频号 且 platform=抖音-视频号）
#   取一条任务，同时发布到抖音（platform=douyin）和视频号（platform=shipinhao），
#   统一走 POST /accounts/publish_video：
#   - profile_name  固定 domestic01（两平台都用，靠 platform 字段区分）
#   - video_url     用 task.oss_url（已签名的 URL，服务端先下载到本地临时文件再发布）
#   - title         用 task.title（已含话题标签，如 #快时尚 #Shein）
# 成功判定：type=="success" 且 status=="completed"（status 才是真实发布结果）
# 全部平台成功 → 任务 status=success；任一失败 → status=failed（error_msg 记录各平台结果）
# 结束后通过钉钉机器人（agic_dw）通知结果
class DomesticHuashengPublishWorker
  # 要发布的主题
  THEME = "花生视频-抖音号视频号"

  # 任务表的 platform 值（抖音+视频号 合并任务）
  PLATFORM = "抖音-视频号"

  # 发布接口主机（抖音/视频号共用）
  PUBLISH_HOST = "http://47.98.149.236:8080"

  # 固定 profile_name
  PROFILE_NAME = "domestic01"

  # 发布目标：平台名 → platform 标识（顺序即通知里的展示顺序）
  TARGETS = {
    "抖音"  => "douyin",
    "视频号" => "shipinhao"
  }.freeze

  # 钉钉机器人（agic_dw 已在 config/dingtalk.yml 配置）
  NOTIFY_ROBOT = :agic_dw

  # HTTP 超时（秒）
  OPEN_TIMEOUT = 30
  READ_TIMEOUT = 900   # 发布流程超时上限 15 分钟

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

      # 依次发布抖音、视频号，每次 API 调用间隔 40-60 秒
      results = {}
      TARGETS.each do |platform_name, platform_key|
        result = publish(task, platform_key, platform_name)
        Rails.logger.info "[DySphHuashengPublishWorker] #{platform_name} 发布结果: #{result.inspect}"

        # 连不上：直接结束，钉钉通知，任务保持 pending
        if result[:special] == :connection_failed
          notify_connection_failed(task, platform_name, result)
          Rails.logger.info "[DySphHuashengPublishWorker] 发布接口连不上，任务 id=#{task.id} 保持 pending，本次结束"
          return
        end

        results[platform_name] = result

        # 每次 API 调用间隔 40-60 秒（最后一个平台后不再等待）
        sleep(rand(40..60)) unless platform_name == TARGETS.keys.last
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

    # 发布到指定平台（统一走 POST /accounts/publish_video）
    # @return [Hash] { success:, message:, special: nil/:connection_failed/:undetectable/:other_error }
    def publish(task, platform_key, platform_name)
      body = {
        profile_name: PROFILE_NAME,
        platform:     platform_key,
        video_url:    task.oss_url.to_s,
        title:        task.title.to_s
      }
      url = "#{PUBLISH_HOST}/accounts/publish_video"
      Rails.logger.info "[DySphHuashengPublishWorker] [#{platform_name}] 请求 #{url} body=#{body.to_json}"

      result = parse_result(http_post_json(url, body))

      case result[:special]
      when :connection_failed
        # 连不上：不重试，直接返回
        result
      when :undetectable
        # 指纹浏览器刚关未反应过来：等 30 秒重试一次
        Rails.logger.info "[DySphHuashengPublishWorker] [#{platform_name}] undetectable_path 错误，30 秒后重试"
        sleep 30
        parse_result(http_post_json(url, body))
      when :other_error
        # 其他报错：等 60 秒重试一次
        Rails.logger.info "[DySphHuashengPublishWorker] [#{platform_name}] 报错(#{result[:message]})，60 秒后重试"
        sleep 60
        parse_result(http_post_json(url, body))
      else
        result # 成功
      end
    end

    # 解析发布响应：成功 / 连不上 / undetectable 错误 / 其他报错
    # 成功判定：type 只表示「请求被处理」，status=="completed" 才是真正发布成功
    def parse_result(response)
      if response.is_a?(Hash) && response["network_error"]
        { success: false, message: response["error_info"].to_s, special: :connection_failed }
      elsif response.is_a?(Hash) && response["type"] == "success" && response["status"] == "completed"
        { success: true, message: "成功", special: nil }
      else
        err = extract_error(response)
        if err.include?("undetectable_path")
          { success: false, message: err, special: :undetectable }
        else
          { success: false, message: err, special: :other_error }
        end
      end
    end

    # 发布结束后更新任务状态：全部平台成功 → success；任一失败 → failed
    # undetectable 重试后仍失败 → 不置失败，保持 pending 等下次调度重试（指纹浏览器临时状态）
    # 注：这类抖音-视频号任务不走账号分配，account_id 恒为空；
    #     而 model 有「非 pending 必须有账号」的校验，故用 save(validate: false) 绕过
    def update_task_status(task, results)
      if results.values.any? { |r| r[:special] == :undetectable }
        task.error_msg = results.map { |k, r| "#{k}:#{r[:success] ? "成功" : "失败(#{r[:message]})"}" }.join("；")
        task.save(validate: false)
        Rails.logger.info "[DySphHuashengPublishWorker] undetectable 错误重试后仍失败，任务 id=#{task.id} 保持 pending 不置失败"
        return
      end

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

    # POST JSON，返回解析后的响应
    # 网络层异常（连不上/超时/域名解析失败等）标记 network_error: true，供上层识别「发布接口连不上」
    def http_post_json(endpoint, body)
      response = RemoteApiClient.post(endpoint, body, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      JSON.parse(response.body.to_s.dup.force_encoding('UTF-8'))
    rescue JSON::ParserError => e
      { "type" => "error", "error_info" => "响应非JSON: #{e.message}" }
    rescue => e
      { "type" => "error", "network_error" => true, "error_info" => "#{e.class} #{e.message}" }
    end

    # 提取失败原因（优先 error_info，其次 status，最后 error/message/响应原文）
    def extract_error(response)
      return response.to_s unless response.is_a?(Hash)
      return response["error_info"] if response["error_info"].present?
      return "status=#{response["status"]}" if response["status"].present? && response["status"] != "completed"
      response["error"] || response["message"] || response.to_json
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

    # 发布接口连不上时的通知
    def notify_connection_failed(task, platform_name, result)
      keyword = task.keyword.to_s.split("|").first.to_s.strip
      keyword = task.keyword.to_s if keyword.empty?
      Dingtalk.send_text(NOTIFY_ROBOT, "#{keyword}:发布接口连不上(#{platform_name})，任务保持 pending，本次跳过")
    end

    private

    def platform_result_text(result)
      return "成功" if result[:success]
      case result[:special]
      when :connection_failed then "发布接口连不上"
      when :undetectable then "undetectable错误(重试后仍失败)"
      else "失败(#{result[:message]})"
      end
    end

    def setup_logger
      logger = ActiveSupport::Logger.new(File.join(Rails.root, LOG_FILE))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
