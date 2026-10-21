class Admin::HostingAccountsController < Admin::BaseController
  before_action :set_hosting_account, only: [:show, :edit, :update, :destroy]
  before_action :load_form_options, only: [:new, :create, :edit, :update]

  def index
    @q = HostingAccount.ransack(params[:q])
    @hosting_accounts = @q.result.includes(:client).order(created_at: :desc).page(params[:page])
  end

  def new
    @hosting_account = HostingAccount.new
  end

  def create
    @hosting_account = HostingAccount.new(hosting_account_params)
    if @hosting_account.save
      redirect_to admin_hosting_accounts_path, notice: '托管账号已添加'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @hosting_account.update(hosting_account_params)
      redirect_to admin_hosting_accounts_path, notice: '托管账号已更新'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @hosting_account.destroy
    redirect_to admin_hosting_accounts_path, notice: '托管账号已删除'
  end

  private

  def set_hosting_account
    @hosting_account = HostingAccount.find(params[:id])
  end

  def load_form_options
    @clients = Client.order(:name)
    @resource_queues = WorkMode.resource_modes.map { |m| [m.name, m.key] }
  end

  def hosting_account_params
    params.require(:hosting_account).permit(
      :client_id, :platform, :theme, :resource_queue, :publish_channel, :status, :remark
    )
  end
end
