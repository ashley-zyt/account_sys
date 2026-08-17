class Util
  def self.tmp_fun
    theme = "大熊猫Baobao"
    title = "Not perfect. Still iconic. 🐼 #BaoBao #DanceTrend #Confidence #PandaTok #FunnyPanda #TrendingNow"
    description = "Not perfect. Still iconic. 🐼"
    oss_url = "http://operation-viodes.oss-cn-hangzhou.aliyuncs.com/d9693de2-09a9-4b18-beff-6d6e89e093fb_178237487.mp4?OSSAccessKeyId=LTAI5tFKwps3PgNdpi69ab7p&Expires=1813910997&Signature=rDYuhCTA9NT4nNaa0mCyk0rFMhM%3D"
    platforms = %w[facebook twitter tiktok instagram]
    group_id = SecureRandom.uuid
    platforms.each do |platform|
    OperationTask.create(
    theme: theme,
    title: title,
    oss_url: oss_url,
    platform: platform,
    status: :pending,
    group_id: group_id
    )
    end
    OperationTask.create(
    theme: theme,
    title: description,
    description: title,
    oss_url: oss_url,
    platform: "youtube",
    status: :pending,
    group_id: group_id
    )
  end

  # ===== 临时方法：给指定账号分配资源并立即运行发布 =====
  # 使用方式：
  #   1. 按账号 ID：Util.assign_and_publish_account(account_id: 123)
  #   2. 按账号名：Util.assign_and_publish_account(account_name: 'xxx')
  # 流程：
  #   - 校验账号状态（必须正常、绑定浏览器、浏览器有 machine_ip）
  #   - TikTok 会跳过 0 浏览量冷却期账号（可传 skip_tiktok_check: true 强制分配）
  #   - 按账号 work_type 找同平台同主题的 pending 资源分配为 waiting_publish
  #   - 调用 PublishScheduler 直接执行该单条任务
  # @return [Hash] { success: bool, message: string, task: assigned_task_or_nil }
  def self.assign_and_publish_account(account_id: nil, account_name: nil, skip_tiktok_check: false)
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'util_assign_publish.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    account = if account_id.present?
                Account.find_by(id: account_id)
              elsif account_name.present?
                Account.find_by(account_name: account_name)
              end

    unless account
      msg = "账号不存在：account_id=#{account_id}, account_name=#{account_name}"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    unless account.status == "正常"
      msg = "账号状态异常：#{account.account_name} 当前状态=#{account.status}，仅 正常 账号可分配资源"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    unless account.browser.present?
      msg = "账号 #{account.account_name} 未绑定浏览器，无法分配资源"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    unless account.browser.machine_ip.present?
      msg = "账号 #{account.account_name} 绑定的浏览器 #{account.browser.profile_name} 未设置 machine_ip，无法发布"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    work_type = account.work_type
    task_model_map = {
      "视频搬运" => MoveTask,
      "人工运营" => OperationTask,
      "Grok"     => GrokTask,
      "Heygen"   => HeygenTask,
      "剪映"     => JianyingTask,
      "coze"     => nil
    }
    task_model = task_model_map[work_type]
    unless task_model
      msg = "账号 #{account.account_name} 的工作模式=#{work_type} 暂不支持分配资源"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    today_start = Date.today.beginning_of_day
    today_end   = Date.today.end_of_day
    if task_model.exists?(account_id: account.id, status: :success, actual_publish_time: today_start..today_end)
      msg = "账号 #{account.account_name} 今日已发布成功，跳过分配"
      Rails.logger.info "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    if !skip_tiktok_check && account.platform == "tiktok" && account.zero_views_in_past_3_days?
      msg = "TikTok账号 #{account.account_name} 过去3天发文浏览量均为0，按规则暂停分配；如需强制分配请传 skip_tiktok_check: true"
      Rails.logger.warn "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    pending_task = task_model.where(status: :pending, platform: account.platform, theme: account.theme).order(created_at: :asc).first
    unless pending_task
      msg = "账号 #{account.account_name}[#{account.platform}-#{account.theme}-#{work_type}] 暂无可用 pending 资源"
      Rails.logger.warn "[Util] #{msg}"
      return { success: false, message: msg, task: nil }
    end

    assigned_task = nil
    ActiveRecord::Base.transaction do
      pending_task.lock!
      pending_task.update!(
        account_id: account.id,
        browser_id: account.browser_id,
        status: :waiting_publish
      )
      assigned_task = pending_task.reload
    end

    type_name = work_type
    Rails.logger.info "[Util] 账号 #{account.account_name} 分配 #{type_name} 资源成功，任务 ID=#{assigned_task.id}，开始执行发布..."

    machine_ip = account.browser.machine_ip
    task_type  = PublishScheduler.task_type_name(assigned_task)

    ActiveRecord::Base.transaction do
      assigned_task.lock!
      assigned_task.update!(status: :executing, start_at: Time.current)
    end

    PublishScheduler.execute_task(assigned_task, task_type, machine_ip)

    assigned_task.reload
    status_text = assigned_task.status == "success" ? "成功" : (assigned_task.status == "failed" ? "失败" : assigned_task.status.to_s)
    msg = "账号 #{account.account_name} 发布执行完成，任务 ID=#{assigned_task.id}，最终状态=#{status_text}"
    Rails.logger.info "[Util] #{msg}"

    { success: assigned_task.status == "success", message: msg, task: assigned_task }
  end

  # ===== 获取指定账号的发文数据 =====
  # 使用方式：
  #   1. 按账号 ID：Util.fetch_account_post_data(account_id: 123)
  #   2. 按账号名：Util.fetch_account_post_data(account_name: 'xxx')
  # 流程：
  #   - 校验账号存在、绑定浏览器、浏览器有 machine_ip
  #   - 向运营机器推送采集指令 http://<machine_ip>:8080/accounts/fetch_posts
  #   - 采集端收到指令后会自行采集数据，并通过 API 接口回传结果
  #   - 本方法仅负责推送指令，不处理返回数据的落库
  # @return [Hash] { success: bool, message: string, response: string_or_nil }
  def self.fetch_account_post_data(account_id: nil, account_name: nil)
    logger = ActiveSupport::Logger.new(File.join(Rails.root, 'log', 'util_fetch_post_data.log'))
    logger.formatter = Rails.logger.formatter
    Rails.logger = logger

    account = if account_id.present?
                Account.find_by(id: account_id)
              elsif account_name.present?
                Account.find_by(account_name: account_name)
              end

    unless account
      msg = "账号不存在：account_id=#{account_id}, account_name=#{account_name}"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, response: nil }
    end

    unless account.browser.present?
      msg = "账号 #{account.account_name} 未绑定浏览器，无法采集发文数据"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, response: nil }
    end

    machine_ip = account.browser.machine_ip
    unless machine_ip.present?
      msg = "账号 #{account.account_name} 绑定的浏览器 #{account.browser.profile_name} 未设置 machine_ip，无法采集"
      Rails.logger.error "[Util] #{msg}"
      return { success: false, message: msg, response: nil }
    end

    payload = {
      id: account.browser.id,
      profile_name: account.browser.profile_name,
      active_accounts: [
        {
          id: account.id,
          platform: account.platform,
          source_url: account.source_url,
          work_type: account.work_type
        }
      ]
    }

    endpoint = "http://#{machine_ip}:8080/accounts/fetch_posts"
    Rails.logger.info "[Util] 账号 #{account.account_name}(#{account.platform}) 推送采集指令 → #{endpoint}"

    result = PostDatas.push_to_external_with_retry(payload, endpoint)

    if result[:success]
      # 打印API返回结果（仅记录，落库由采集端通过API接口完成）
      Rails.logger.info "[Util] 账号 #{account.account_name} 采集指令推送成功，返回: #{result[:response].to_s[0..2000]}"
      msg = "账号 #{account.account_name} 采集指令推送成功"
      { success: true, message: msg, response: result[:response] }
    else
      msg = "账号 #{account.account_name} 采集指令推送失败: #{result[:error]}"
      Rails.logger.error "[Util] #{msg}"
      { success: false, message: msg, response: nil }
    end
  rescue => e
    msg = "账号采集发文数据异常: #{e.message}"
    Rails.logger.error "[Util] #{msg}"
    { success: false, message: msg, response: nil }
  end

  # ===== 获取今日未更新数据的账号 =====
  # 账号范围：系统中状态为"正常"的所有账号
  # 判断逻辑：
  #   - post_stats 最新一条记录的 data_updated_at 日期不是今天（或无记录）
  #   - account_stat 最新一条记录的 stat_date 不是今天（或无记录）
  # @return [Hash] {
  #   post_stats_stale: [account_ids...],   # post_stats最新更新不是今天的账号
  #   stat_stale: [account_ids...],         # account_stat最新快照不是今天的账号
  #   both_stale: [account_ids...],         # 两者都不是今天的账号（交集）
  #   total: N                               # 正常状态账号总数
  # }
  def self.get_stale_accounts
    today = Date.today
    today_start = today.beginning_of_day
    today_end = today.end_of_day

    # 所有状态为"正常"的账号
    all_account_ids = Account.where(status: Account.statuses['正常']).where.not(platform: Account.platforms['facebook']).pluck(:id).uniq

    # 1. post_stats 最新 data_updated_at 是今天的账号ID
    post_updated_today = PostStat.where(account_id: all_account_ids)
                                 .group(:account_id)
                                 .having("MAX(data_updated_at) >= ? AND MAX(data_updated_at) <= ?", today_start, today_end)
                                 .pluck(:account_id)
    post_stats_stale = all_account_ids - post_updated_today

    # 2. account_stat 最新 stat_date 是今天的账号ID
    stat_updated_today = AccountStat.where(account_id: all_account_ids)
                                    .group(:account_id)
                                    .having("MAX(stat_date) = ?", today)
                                    .pluck(:account_id)
    stat_stale = all_account_ids - stat_updated_today

    # 3. 两者都不是今天的账号（交集）
    both_stale = post_stats_stale & stat_stale

    Rails.logger.info "[Util] 未更新账号统计 - 正常账号总数: #{all_account_ids.size}, " \
                      "post_stats最新不是今天: #{post_stats_stale.size}, " \
                      "account_stat最新不是今天: #{stat_stale.size}, " \
                      "两者都不是今天: #{both_stale.size}"

    {
      post_stats_stale: post_stats_stale.sort,
      stat_stale: stat_stale.sort,
      both_stale: both_stale.sort,
      total: all_account_ids.size,
      post_updated_count: post_updated_today.size,
      stat_updated_count: stat_updated_today.size
    }
  end
end