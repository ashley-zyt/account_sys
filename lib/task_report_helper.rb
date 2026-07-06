# 任务报告帮助模块
# 提取 report 接口中的业务逻辑，供发布调度器等其他模块复用
module TaskReportHelper

  def self.create_task_log(task, status, snapshot_account_id, snapshot_browser_id, error_msg = nil)
    task_status = status == 'success' ? "success" : "failed"

    TaskLog.create!(
      task_uuid: task.task_uuid,
      account_id: snapshot_account_id,
      browser_id: snapshot_browser_id,
      response_data: { status: status, error_msg: error_msg }.to_s,
      status: task_status,
      error_msg: error_msg,
      run_at: Time.current
    )

    if error_msg.present?
      check_account_abnormal(snapshot_account_id, error_msg)
      check_hhcat_login_failure
    end
  end

  def self.check_account_abnormal(account_id, error_msg)
    return unless account_id.present?

    abnormal_keywords = [
      "not logged in",
      "account verification",
      "some of your media failed to upload",
      "account banned or human verification required",
      "account verification required after upload",
      "Confirm you're human",
      "账号未登录",
      "账号验证",
      "账号封禁"
    ]

    if abnormal_keywords.any? { |keyword| error_msg.include?(keyword) }
      Account.where(id: account_id).update_all(status: 2)
      Rails.logger.warn "[TaskReportHelper] 账号 #{account_id} 检测到异常，已标记为异常状态"
    end
  end

  def self.check_hhcat_login_failure
    five_minutes_ago = Time.current - 5.minutes
    recent_errors = TaskLog.where("error_msg LIKE '%哼哼猫未登陆成功%' AND created_at >= ?", five_minutes_ago).order(id: :desc).limit(5)

    if recent_errors.size >= 5
      OperationTask.where(status: :waiting_publish).update_all(
        status: :pending,
        account_id: nil,
        browser_id: nil
      )
      MoveTask.where(status: :waiting_publish).update_all(
        status: :pending,
        account_id: nil,
        browser_id: nil
      )

      send_dingding_alert("【养号】检测到连续5次哼哼猫未登录成功", "已自动将所有待执行任务重置为未分配状态")
    end
  end

  def self.send_dingding_alert(title, content)
    webhook_url = ENV['DINGDING_WEBHOOK_URL']
    return unless webhook_url.present?

    begin
      uri = URI.parse(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      message = {
        msgtype: "markdown",
        markdown: {
          title: title,
          text: "## #{title}\n\n#{content}"
        }
      }

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request.body = message.to_json

      http.request(request)
      Rails.logger.info "[TaskReportHelper] 钉钉消息发送成功"
    rescue => e
      Rails.logger.error "[TaskReportHelper] 钉钉消息发送失败: #{e.message}"
    end
  end

  def self.update_task_status(task, status, error_msg = nil)
    ActiveRecord::Base.transaction do
      if status == 'success'
        task.update!(
          status: :success,
          actual_publish_time: Time.current,
          error_msg: nil
        )
      else
        if task.is_a?(OperationTask) || task.is_a?(GrokTask) || task.is_a?(HeygenTask)
          task.update!(
            status: :pending,
            account_id: nil,
            browser_id: nil,
            error_msg: error_msg,
            start_at: nil
          )
        else
          task.update!(
            status: :failed,
            error_msg: error_msg
          )
        end
      end
    end
  end

end