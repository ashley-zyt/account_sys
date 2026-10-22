# 客户托管发布调度器。
#
# 每天 7 点开始，遍历「托管中 + 已配置渠道 + 已授权」的托管账号：
#   1. 按账号「资源队列 + 主题 + 平台」取一条未消费成品，生成托管发布任务
#   2. 按账号发布渠道（postpeer/postforme/x_api）执行发布
#   3. 每个账号处理完 sleep 固定间隔，避免第三方平台限流
#
# 频次：REQUEST_INTERVAL 为每次处理完一个账号后的主动间隔（秒）。
#       第三方 API 内部另有 30 秒请求节流兜底，二者叠加保证不触发限流。
module HostingPublishScheduler
  # 处理完一个账号后的主动间隔（秒），与第三方平台 30 秒节流对齐
  REQUEST_INTERVAL = 30

  class << self
    def run
      setup_logger('hosting_publish_scheduler.log')
      Rails.logger.info "[HostingPublishScheduler] 开始托管发布扫描"

      accounts = active_authorized_accounts
      Rails.logger.info "[HostingPublishScheduler] 待处理托管账号 #{accounts.size} 个"

      accounts.each_with_index do |account, idx|
        process_account(account)
        sleep REQUEST_INTERVAL if idx < accounts.size - 1
      end

      Rails.logger.info "[HostingPublishScheduler] 托管发布扫描完成"
    end

    # 待发布的托管账号：托管中 + 已配置渠道 + 已授权
    def active_authorized_accounts
      HostingAccount.where(status: :active).order(:id).select do |a|
        a.publish_channel.present? && HostingPublishService.authorized?(a)
      end
    end

    # 处理单个托管账号：取成品生成任务 → 发布
    def process_account(account)
      result = HostingPublishService.fetch_and_create_task(account)
      unless result[:success]
        Rails.logger.info "[HostingPublishScheduler] 托管账号 #{account.id} 生成任务失败：#{result[:message]}"
        return
      end

      publish_result = HostingPublishService.publish(result[:task])
      if publish_result[:success]
        Rails.logger.info "[HostingPublishScheduler] 托管账号 #{account.id} 发布成功：#{publish_result[:message]}"
      else
        Rails.logger.info "[HostingPublishScheduler] 托管账号 #{account.id} 发布失败：#{publish_result[:message]}"
      end
    rescue => e
      Rails.logger.error "[HostingPublishScheduler] 托管账号 #{account.id} 处理异常: #{e.message}"
    end

    def setup_logger(file)
      logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', file))
      logger.formatter = Rails.logger.formatter
      Rails.logger = logger
    end
  end
end
