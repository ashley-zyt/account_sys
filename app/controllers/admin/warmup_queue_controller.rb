class Admin::WarmupQueueController < Admin::BaseController
  def index
    @q = Account.ransack(params[:q])
    @accounts = @q.result(distinct: true)
                  .includes(:warmup_profile, :browser)
                  .order(updated_at: :desc)
                  .page(params[:page])
                  .per(20)
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
