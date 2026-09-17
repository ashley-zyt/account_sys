# 今日发文状况统计（供脚本 scripts/publish_daily_summary.rb 与后台「今日发布状况」弹窗复用）
#
# 口径（参考账号列表页「最后一次是否成功」）：
#   - 正常账号数：Account.status = 0（正常）的账号数，按平台分组
#   - 今日成功/失败：按「账号」去重，取每个账号今日最后一次发文日志（run_at 最大的那条）
#     的 status 作为该账号今日的最终结果。失败重试后成功的，以最后一次为准。
#   - 平台归属：优先用日志的 account_id 快照关联 accounts.platform；
#     账号已物理删除的，回退用 task_uuid 关联任务表(MoveTask等)的 platform。
#
# 注意：pluck 对 enum 列(platform/status)返回的是 enum 名称字符串，不是整数。
class PublishDailySummary
  PLATFORM_NAMES = {
    "facebook"  => "Facebook",
    "twitter"   => "X",
    "tiktok"    => "TikTok",
    "youtube"   => "YouTube",
    "instagram" => "Instagram"
  }.freeze

  # 计算某天的发文统计
  # @param date [Date] 统计日期，默认今天
  # @return [Hash] { date:, platforms:, total:, failed_accounts: }
  #   platforms: [{ key:, name:, normal:, success:, failed: }]
  #   failed_accounts: [{ account_id:, account_name:, platform: }]
  def self.compute(date = Date.today)
    today_start = date.beginning_of_day
    today_end = date.end_of_day

    # 1. 各平台正常账号数（group 对 enum 列返回 enum 名称 key）
    normal_counts = Account.where(status: 0).group(:platform).count

    # 2. 当日发文日志，按账号取「最后一次」执行结果
    rows = TaskLog.where(run_at: today_start..today_end)
                  .pluck(:account_id, :status, :run_at, :task_uuid)

    last_by_account = {}
    rows.each do |account_id, status, run_at, task_uuid|
      next if account_id.nil?
      cur = last_by_account[account_id]
      if cur.nil? || (run_at && (!cur[:run_at] || run_at > cur[:run_at]))
        last_by_account[account_id] = { status: status, run_at: run_at, task_uuid: task_uuid }
      end
    end

    # 3. 账号 id → 平台名称（pluck 返回 enum 名称，直接用）
    account_ids = last_by_account.keys
    platform_by_account = {}
    Account.unscoped.where(id: account_ids).pluck(:id, :platform).each do |id, p|
      platform_by_account[id] = p
    end

    # 4. 回退：账号已物理删除的，用 task_uuid 关联任务表拿 platform
    missing_uuids = last_by_account
                    .select { |id, _e| platform_by_account[id].nil? }
                    .map { |_id, e| e[:task_uuid] }
                    .compact.uniq
    task_platform_by_uuid = {}
    unless missing_uuids.empty?
      WorkMode.resource_modes.each do |mode|
        mode.task_model_class.where(task_uuid: missing_uuids).pluck(:task_uuid, :platform).each do |uuid, p|
          task_platform_by_uuid[uuid] = p if p.present?
        end
      end
    end
    last_by_account.each do |id, e|
      platform_by_account[id] = task_platform_by_uuid[e[:task_uuid]] if platform_by_account[id].nil?
    end

    # 5. 按平台统计成功/失败，并记录最终失败的账号
    success_counts = Hash.new(0)
    failed_counts = Hash.new(0)
    failed_account_ids = {}
    last_by_account.each do |account_id, e|
      platform = platform_by_account[account_id]
      if e[:status].to_s == "success"
        success_counts[platform] += 1
      else
        failed_counts[platform] += 1
        failed_account_ids[account_id] = platform
      end
    end

    # 失败账号详情（含账号名，账号已删则 name 为 nil）
    failed_accounts = failed_account_ids.map do |account_id, platform|
      acc = Account.unscoped.find_by(id: account_id)
      {
        account_id: account_id,
        account_name: acc&.account_name,
        platform: platform
      }
    end
    failed_accounts.sort_by! { |f| [f[:platform].to_s, f[:account_id].to_i] }

    platforms = PLATFORM_NAMES.map do |key, name|
      {
        key: key,
        name: name,
        normal: normal_counts[key] || 0,
        success: success_counts[key] || 0,
        failed: failed_counts[key] || 0
      }
    end

    {
      date: date,
      platforms: platforms,
      total: {
        normal: platforms.sum { |p| p[:normal] },
        success: platforms.sum { |p| p[:success] } + (success_counts[nil] || 0),
        failed: platforms.sum { |p| p[:failed] } + (failed_counts[nil] || 0)
      },
      failed_accounts: failed_accounts
    }
  end
end
