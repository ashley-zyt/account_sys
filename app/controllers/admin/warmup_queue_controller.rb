class Admin::WarmupQueueController < Admin::BaseController
  def index
    @q = Account.ransack(params[:q])
    @accounts = @q.result(distinct: true)
                  .includes(:warmup_profile, :browser)
                  .joins(:warmup_profile)
                  .where.not(status: [1, 2])  # 默认剔除未登录(1)和封禁/停用(2)的账号
                  .order(Arel.sql("warmup_profiles.last_warmup_at IS NULL DESC, warmup_profiles.last_warmup_at ASC"))
                  .page(params[:page])
                  .per(20)

    # 按机器分类统计
    # 搬运机器
    @move_total = Account.joins(:warmup_profile).where(status: [0, 3], warmup_profiles: { machine: 'move' }).count
    @move_enabled = WarmupProfile.where(machine: 'move', warmup_enabled: true).count
    @move_due = Account.joins(:warmup_profile).where(warmup_profiles: { machine: 'move', warmup_enabled: true }).where("warmup_profiles.last_warmup_at IS NULL OR warmup_profiles.last_warmup_at < ?", 48.hours.ago).count

    # 运营机器
    @other_total = Account.joins(:warmup_profile).where(status: [0, 3], warmup_profiles: { machine: 'other' }).count
    @other_enabled = WarmupProfile.where(machine: 'other', warmup_enabled: true).count
    @other_due = Account.joins(:warmup_profile).where(warmup_profiles: { machine: 'other', warmup_enabled: true }).where("warmup_profiles.last_warmup_at IS NULL OR warmup_profiles.last_warmup_at < ?", 48.hours.ago).count

    # 总计
    @total_count = Account.where(status: [0, 3]).count
    @enabled_count = WarmupProfile.where(warmup_enabled: true).count
    @never_warmed = Account.joins(:warmup_profile).where(warmup_profiles: { warmup_enabled: true, last_warmup_at: nil }).count
    @due_count = Account.joins(:warmup_profile).where(warmup_profiles: { warmup_enabled: true }).where("warmup_profiles.last_warmup_at IS NULL OR warmup_profiles.last_warmup_at < ?", 48.hours.ago).count
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
