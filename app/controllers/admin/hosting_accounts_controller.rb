class Admin::HostingAccountsController < Admin::BaseController
  before_action :set_hosting_account, only: [:update, :destroy, :start_postpeer_auth, :confirm_postpeer_auth, :create_task]
  before_action :load_form_options, only: [:new_modal, :edit_modal, :create, :update]

  def index
    @q = HostingAccount.ransack(params[:q])
    @hosting_accounts = @q.result.includes(:client).order(created_at: :desc).page(params[:page])
  end

  def create
    @hosting_account = HostingAccount.new(hosting_account_params)
    respond_to do |format|
      if @hosting_account.save
        format.html { redirect_to admin_hosting_accounts_path, notice: '托管账号已添加' }
        format.json { render json: { success: true, message: '托管账号已添加' } }
      else
        format.html { render :new_modal, layout: false, status: :unprocessable_entity }
        format.json { render json: { success: false, message: @hosting_account.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @hosting_account.update(hosting_account_params)
        format.html { redirect_to admin_hosting_accounts_path, notice: '托管账号已更新' }
        format.json { render json: { success: true, message: '托管账号已更新' } }
      else
        format.html { render :edit_modal, layout: false, status: :unprocessable_entity }
        format.json { render json: { success: false, message: @hosting_account.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @hosting_account.destroy
    redirect_to admin_hosting_accounts_path, notice: '托管账号已删除'
  end

  def new_modal
    @hosting_account = HostingAccount.new
    render layout: false
  end

  def edit_modal
    @hosting_account = HostingAccount.find(params[:id])
    render layout: false
  end

  # 发起 postpeer 授权（全手动，不做机器端动作）：生成授权链接供人工完成 OAuth
  def start_postpeer_auth
    result = HostingPostpeerAuthService.start_authorization(@hosting_account)
    if result[:success]
      flash[:hosting_auth_url] = result[:auth_url]
      redirect_back fallback_location: admin_hosting_accounts_path, notice: result[:message]
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: result[:message]
    end
  end

  # 确认 postpeer 授权：反查 accountId 标记「已授权」
  def confirm_postpeer_auth
    result = HostingPostpeerAuthService.confirm_authorization(@hosting_account)
    if result
      redirect_back fallback_location: admin_hosting_accounts_path, notice: "postpeer 授权成功（peer_account_id=#{result[:peer_account_id]}）"
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: 'postpeer 授权未完成，请先完成 OAuth 后再试'
    end
  end

  # 手动触发：从资源队列取一条成品，生成托管发布任务
  def create_task
    result = HostingPublishService.fetch_and_create_task(@hosting_account)
    if result[:success]
      redirect_back fallback_location: admin_hosting_accounts_path, notice: "已生成托管发布任务 ##{result[:task].id}"
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: result[:message]
    end
  end

  private

  def set_hosting_account
    @hosting_account = HostingAccount.find(params[:id])
  end

  def load_form_options
    @clients = Client.order(:name)
    @themes = Theme.order(:name).pluck(:name)
    @resource_queues = WorkMode.resource_modes.map(&:name)
  end

  def hosting_account_params
    raw = params.require(:hosting_account).permit(
      :client_name, :platform, :theme, :resource_queue, :publish_channel, :status, :remark
    )

    attrs = {
      platform: raw[:platform],
      theme: raw[:theme].presence,
      publish_channel: raw[:publish_channel].presence,
      status: raw[:status],
      remark: raw[:remark]
    }

    if raw[:client_name].present?
      attrs[:client_id] = Client.find_by(name: raw[:client_name])&.id
    end

    rq = raw[:resource_queue].to_s.strip
    if rq.present?
      wm = WorkMode.resource_modes.find { |m| m.name == rq }
      attrs[:resource_queue] = wm ? wm.key : rq
    end

    attrs
  end
end
