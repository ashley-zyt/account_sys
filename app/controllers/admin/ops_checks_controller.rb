# 运维排查页：把高频的临时检查脚本沉淀为页面
#   Tab1 未采集发文账号：指定日期没有 post_stat 数据的账号 + 当天是否有发文成功任务 + 所属机器
#        （排查「发布成功但没采集到数据」）
#   Tab2 浏览器发布失败 Top：近 N 天 ag_center 渠道发布失败超过阈值的账号 + 高频错误
class Admin::OpsChecksController < Admin::BaseController
  DEFAULT_DAYS = 7      # 失败统计回溯天数
  DEFAULT_THRESHOLD = 7 # 失败次数阈值
  DEFAULT_DATE = Date.yesterday

  def index
    @check_date = parse_date(params[:date]) || DEFAULT_DATE
    @days = (params[:days].presence || DEFAULT_DAYS).to_i
    @threshold = (params[:threshold].presence || DEFAULT_THRESHOLD).to_i
    @platform = params[:platform].presence

    @missing_items = fetch_missing_stats_accounts(@check_date, @platform, params[:all_status] == "1")
    @failure_items = fetch_browser_failure_accounts(@days, @threshold, @platform)
  end

  # 一键采集：把当前筛选出的「未采集到发文数据」账号推给机器端补采（后台异步执行）。
  # important_only=true 时只采集「重点」账号（当天有成功任务但没数据）。
  def collect_missing
    check_date = parse_date(params[:date]) || DEFAULT_DATE
    platform = params[:platform].presence
    all_status = params[:all_status] == "1"
    important_only = params[:important_only] == "1"

    items = fetch_missing_stats_accounts(check_date, platform, all_status)
    items = items.select { |i| i[:important] } if important_only
    account_ids = items.map { |i| i[:account].id }

    if account_ids.empty?
      redirect_to admin_ops_checks_path(date: check_date, platform: platform, all_status: (all_status ? "1" : nil)),
                  alert: "没有需要采集的账号"
      return
    end

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        account_ids.each do |account_id|
          begin
            Util.fetch_account_post_data(account_id: account_id)
          rescue => e
            Rails.logger.error "[OpsChecks] 采集账号 ##{account_id} 异常: #{e.message}"
          end
        end
      end
    end

    label = important_only ? "重点" : "全部"
    redirect_to admin_ops_checks_path(date: check_date, platform: platform, all_status: (all_status ? "1" : nil)),
                notice: "已开始采集 #{account_ids.size} 个#{label}账号，稍后刷新查看结果"
  end

  private

  def parse_date(value)
    Date.parse(value)
  rescue TypeError, ArgumentError
    nil
  end

  def platform_scope
    Account.platforms.key(@platform) # 非法平台值归一为 nil
  end

  # ===== Tab1：指定日期未采集到发文数据的账号 =====
  def fetch_missing_stats_accounts(date, platform, all_status)
    scope = Account.all
    scope = scope.where(status: "正常") unless all_status
    scope = scope.where(platform: platform_scope) if platform_scope

    ids_with_stats = PostStat.where(post_date: date).distinct.pluck(:account_id).to_set

    # 当天成功发文日志（按账号快照聚合）
    success_rows = TaskLog.where(status: :success, run_at: date.all_day)
                          .where.not(account_id: nil)
                          .pluck(:account_id, :publish_channel, :run_at)
    success_by_account = Hash.new { |h, k| h[k] = [] }
    success_rows.each { |aid, ch, run_at| success_by_account[aid] << [ch, run_at] }

    scope.filter_map do |account|
      next nil if ids_with_stats.include?(account.id)

      logs = success_by_account[account.id]
      {
        account: account,
        important: logs.any?, # 有成功任务但没数据 = 重点排查
        machine: account.browser&.machine_host,
        profile: account.browser&.profile_name,
        success_count: logs.size,
        last_success: logs.map(&:last).compact.max,
        last_channel: logs.map(&:first).compact.last,
        last_stat_date: account.post_stats.maximum(:post_date)
      }
    end.sort_by { |item| [item[:important] ? 0 : 1, -item[:success_count], item[:account].id] }
  end

  # ===== Tab2：近 N 天浏览器发布失败超过阈值的账号 =====
  def fetch_browser_failure_accounts(days, threshold, platform)
    range = days.days.ago.beginning_of_day..Time.current

    base = TaskLog.where(status: :failed, publish_channel: :ag_center, run_at: range)
    base = base.where(account_id: Account.where(platform: platform_scope)) if platform_scope

    fail_counts = base.group(:account_id).count
    fail_detail = base.group(:account_id, :error_msg).count
    success_counts = TaskLog.where(status: :success, publish_channel: :ag_center,
                                   account_id: fail_counts.keys, run_at: range)
                            .group(:account_id).count

    accounts = Account.where(id: fail_counts.keys).index_by(&:id)

    fail_counts.filter_map do |account_id, fail_count|
      account = accounts[account_id]
      next nil if account.nil? || fail_count <= threshold

      top_errors = fail_detail.select { |(id, _), _| id == account_id }
                              .sort_by { |_, c| -c }
                              .first(3)
                              .map { |(_, msg), c| { text: (msg.presence || "（空）").to_s, count: c } }

      {
        account: account,
        machine: account.browser&.machine_host,
        fail_count: fail_count,
        success_count: success_counts[account_id].to_i,
        top_errors: top_errors
      }
    end.sort_by { |item| -item[:fail_count] }
  end
end
