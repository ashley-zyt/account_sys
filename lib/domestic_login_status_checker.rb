# 抖音 / 视频号 账号登录状态检查
#
# 触发方式：每天凌晨 03:30 由 whenever 定时执行（见 config/schedule.rb）
# 手动执行：bundle exec rails runner 'DomesticLoginStatusChecker.run'
#
# 接口：GET /accounts/login_status?profile_name=domestic01&platform=<douyin|shipinhao>
#   - profile_name 固定 domestic01
#   - platform 为 douyin（抖音）/ shipinhao（视频号）
# 返回：{ "type": "success", "profile_name": "domestic01", "platform": "shipinhao", "status": "logged_in" }
#   - status: logged_in(已登录) / not_logged_in(未登录) / abnormal(状态异常)
# 每个平台检查完间隔 60 秒再检查下一个
# 若某平台未登录(not_logged_in)，通过发布结果的钉钉机器人(agic_dw)发消息提醒
class DomesticLoginStatusChecker
  # 运营机器主机（抖音/视频号共用，与发布接口同机器）
  HOST = "http://47.98.149.236:8080"

  # 固定 profile_name
  PROFILE_NAME = "domestic01"

  # 检查目标：平台名 → platform 标识
  PLATFORMS = {
    "抖音"  => "douyin",
    "视频号" => "shipinhao"
  }.freeze

  # 钉钉机器人（与发布结果通知一致，agic_dw）
  NOTIFY_ROBOT = :agic_dw

  # 平台间等待（秒）
  INTERVAL = 60

  # HTTP 超时（秒）
  OPEN_TIMEOUT = 30
  READ_TIMEOUT = 60

  # 日志文件
  LOG_FILE = "log/domestic_login_status.log"

  class << self
    def run
      setup_logger
      Rails.logger.info "[DomesticLoginStatusChecker] ===== start ====="

      results = {}
      PLATFORMS.each do |platform_name, platform_key|
        result = check(platform_key)
        extra = result[:error] ? "（#{result[:error]}）" : ""
        Rails.logger.info "[DomesticLoginStatusChecker] #{platform_name}(#{platform_key}) 登录状态: #{result[:status]}#{extra}"
        results[platform_name] = result

        # 每个平台请求完等待 60 秒（最后一个平台后不再等待）
        sleep(INTERVAL) unless platform_name == PLATFORMS.keys.last
      end

      notify_if_logged_out(results)

      Rails.logger.info "[DomesticLoginStatusChecker] ===== done ====="
    end

    # 检查某个平台的登录状态
    # @return [Hash] { status: "logged_in"/"not_logged_in"/"abnormal", error: nil/String }
    def check(platform_key)
      url = "#{HOST}/accounts/login_status?profile_name=#{PROFILE_NAME}&platform=#{platform_key}"
      Rails.logger.info "[DomesticLoginStatusChecker] 请求 #{url}"
      response = RemoteApiClient.get(url, open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT)
      data = JSON.parse(response.body.to_s.dup.force_encoding('UTF-8'))
      { status: data["status"].to_s, error: nil }
    rescue JSON::ParserError => e
      { status: "abnormal", error: "响应非JSON: #{e.message}" }
    rescue => e
      { status: "abnormal", error: "#{e.class} #{e.message}" }
    end

    # 若某平台未登录，发钉钉提醒
    def notify_if_logged_out(results)
      logged_out = results.select { |_name, r| r[:status] == "not_logged_in" }
      return if logged_out.empty?

      names = logged_out.keys.join("、")
      content = "账号登录状态提醒：#{names}账号已退出登录，请及时处理"
      Dingtalk.send_text(NOTIFY_ROBOT, content)
      Rails.logger.info "[DomesticLoginStatusChecker] #{names} 未登录，已发钉钉提醒"
    end

    private

    def setup_logger
      logger = ActiveSupport::Logger.new(File.join(Rails.root, LOG_FILE))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
