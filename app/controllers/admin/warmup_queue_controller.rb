class Admin::WarmupQueueController < Admin::BaseController
  def index
    @q = Account.ransack(params[:q])
    @accounts = @q.result(distinct: true)
                  .includes(:warmup_profile, :browser)
                  .joins(:warmup_profile)
                  .where.not(status: [1, 2])
                  .order(Arel.sql("warmup_profiles.last_warmup_at IS NULL DESC, warmup_profiles.last_warmup_at ASC"))
                  .page(params[:page])
                  .per(20)

    # 按运营机器 IP（browser.machine_ip）分组统计
    machine_ips = Browser.where.not(machine_ip: [nil, ""]).distinct.pluck(:machine_ip)
    @machine_stats = machine_ips.map do |ip|
      browser_ids = Browser.where(machine_ip: ip).pluck(:id)
      total   = Account.where(browser_id: browser_ids, status: [0, 3]).count
      enabled = Account.joins(:warmup_profile)
                       .where(browser_id: browser_ids, status: [0, 3], warmup_profiles: { warmup_enabled: true })
                       .count
      due     = Account.joins(:warmup_profile)
                       .where(browser_id: browser_ids, status: [0, 3], warmup_profiles: { warmup_enabled: true })
                       .where("warmup_profiles.last_warmup_at IS NULL OR warmup_profiles.last_warmup_at < ?", 48.hours.ago)
                       .count
      { ip: ip, total: total, enabled: enabled, due: due }
    end.sort_by { |s| s[:ip] }

    # 未设置机器IP的浏览器下的账号（需提醒补全）
    @orphan_total = Account.joins(:browser)
                            .where(status: [0, 3])
                            .where(browsers: { machine_ip: [nil, ""] })
                            .count

    # 总计 = 各机器行之和（口径与分机器行完全一致：status [0,3] + 该机器浏览器 + warmup_enabled）
    # 之前总计单独查询时缺 status / browser 过滤，导致总计 > 各机器行之和
    @total_count   = @machine_stats.sum { |s| s[:total] }
    @enabled_count = @machine_stats.sum { |s| s[:enabled] }
    @due_count     = @machine_stats.sum { |s| s[:due] }
  end

  def show
    @account = Account.find(params[:id])
    @warmup_profile = @account.warmup_profile
    @recent_tasks = WarmupTask.where(account_id: @account.id)
                               .order(created_at: :desc)
                               .limit(20)
  end

  def toggle_warmup
    @account = Account.find(params[:id])
    profile = @account.warmup_profile || @account.create_warmup_profile
    profile.update!(warmup_enabled: !profile.warmup_enabled)
    redirect_back fallback_location: admin_warmup_queue_index_path, notice: "养号开关已#{profile.warmup_enabled ? '启用' : '停止'}"
  end
end
