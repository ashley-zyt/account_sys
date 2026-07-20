class Admin::WarmupQueueController < Admin::BaseController
  def index
    @q = Account.ransack(params[:q])
    @accounts = @q.result(distinct: true)
                  .includes(:warmup_profiles, :browser)
                  .order(updated_at: :desc)
                  .page(params[:page])
                  .per(20)
  end

  def show
    @account = Account.find(params[:id])
    @warmup_profiles = @account.warmup_profiles
    @recent_tasks = WarmupTask.where(account_id: @account.id)
                               .order(created_at: :desc)
                               .limit(20)
  end
end
