# 钉钉机器人统一封装（公共方法）
#
# 集中管理钉钉消息发送，供全项目复用：
#   - 支持多个机器人，每个机器人拥有独立的 webhook 地址与关键词（配置在 config/dingtalk.yml）
#   - 发送时自动补齐关键词，满足钉钉「自定义关键词」安全设置
#   - 统一提供 text / markdown 两种消息类型，统一 HTTP 发送、错误处理与日志
#
# 使用示例：
#   Dingtalk.send_text(:yanghao, "检测到浏览器被占用")
#   Dingtalk.send_markdown(:publish_result, "发布结果", "正文内容")
module Dingtalk
  CONFIG_PATH = Rails.root.join('config/dingtalk.yml')

  # 读取全部机器人配置（robots 节点）；文件不存在或为空时返回空哈希
  def self.robots
    @robots ||= begin
      require 'yaml'
      File.exist?(CONFIG_PATH) ? ((YAML.load_file(CONFIG_PATH) || {})['robots'] || {}) : {}
    end
  end

  # 读取指定机器人配置；未找到时返回空哈希
  def self.config_for(robot)
    robots[(robot || :default).to_s] || {}
  end

  # 读取指定机器人的 webhook 地址
  def self.webhook_url(robot)
    config_for(robot)['webhook_url'].presence
  end

  # 读取指定机器人的关键词
  def self.keyword(robot)
    config_for(robot)['keyword'].presence
  end

  # 确保内容包含机器人关键词（钉钉自定义关键词安全设置要求消息内容包含关键词）
  def self.with_keyword(robot, content)
    kw = keyword(robot)
    return content if kw.blank? || content.to_s.include?(kw)
    "#{kw}：#{content}"
  end

  # 发送纯文本消息到指定机器人
  # @param robot   [Symbol/String] 机器人名称，如 :yanghao / :publish_result
  # @param content [String] 消息正文（纯文本）
  # @return [Boolean] 是否发送成功（未配置时返回 false）
  def self.send_text(robot, content)
    url = webhook_url(robot)
    return false unless url
    deliver(url, { msgtype: "text", text: { content: with_keyword(robot, content) } })
  end

  # 发送 markdown 消息到指定机器人（标题会自动补齐关键词）
  # @param robot   [Symbol/String] 机器人名称
  # @param title   [String] 消息标题
  # @param content [String] 消息正文（markdown 语法）
  # @return [Boolean] 是否发送成功（未配置时返回 false）
  def self.send_markdown(robot, title, content)
    url = webhook_url(robot)
    return false unless url
    safe_title = with_keyword(robot, title)
    deliver(url, {
      msgtype: "markdown",
      markdown: {
        title: safe_title,
        text: "## #{safe_title}\n\n#{content}"
      }
    })
  end

  # 统一底层发送：Net::HTTP（标准库，无额外依赖）
  def self.deliver(url, post_body)
    require 'net/http'
    require 'json'
    require 'openssl'

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    # 关闭证书校验（钉钉公网 https 证书有效，保留以兼容内网/代理环境）
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json;charset=utf-8'
    request.body = post_body.to_json

    response = http.request(request)
    Rails.logger.info "[Dingtalk] 消息发送完成 status=#{response.code} body=#{response.body}"
    true
  rescue => e
    Rails.logger.error "[Dingtalk] 消息发送失败: #{e.message}"
    false
  end
end
