class Admin::HostingAccountsController < Admin::BaseController
  before_action :set_hosting_account, only: [:update, :destroy, :start_postpeer_auth, :confirm_postpeer_auth, :start_postforme_auth, :confirm_postforme_auth, :start_x_auth, :complete_x_auth, :create_task]
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

  # 发起 postforme 授权（全手动，不做机器端动作）：生成授权链接供人工完成 OAuth
  def start_postforme_auth
    result = HostingPostformeAuthService.start_authorization(@hosting_account)
    if result[:success]
      flash[:hosting_postforme_auth_url] = result[:auth_url]
      redirect_back fallback_location: admin_hosting_accounts_path, notice: result[:message]
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: result[:message]
    end
  end

  # 确认 postforme 授权：反查 social_account_id 标记「已授权」
  def confirm_postforme_auth
    result = HostingPostformeAuthService.confirm_authorization(@hosting_account)
    if result
      redirect_back fallback_location: admin_hosting_accounts_path, notice: "postforme 授权成功（social_account_id=#{result[:social_account_id]}）"
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: 'postforme 授权未完成，请先完成 OAuth 后再试'
    end
  end

  # 发起 X 认证（全手动，不做机器端动作）：生成授权链接供人工完成 OAuth
  def start_x_auth
    result = HostingXAuthService.start_authorization(@hosting_account)
    if result[:success]
      flash[:hosting_x_auth_url] = result[:auth_url]
      redirect_back fallback_location: admin_hosting_accounts_path, notice: result[:message]
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: result[:message]
    end
  end

  # 完成 X 认证：粘贴授权码或整段回调 URL，解析后换 token
  def complete_x_auth
    raw = params[:code].to_s.strip
    if raw.blank?
      return redirect_back fallback_location: admin_hosting_accounts_path, alert: '请粘贴授权码或回调 URL'
    end

    code, state = parse_manual_auth_input(raw)
    if code.blank?
      return redirect_back fallback_location: admin_hosting_accounts_path, alert: '无法从粘贴内容中解析出授权码'
    end

    result = HostingXAuthService.complete_authorization(@hosting_account, code: code, state: state)
    if result[:success]
      redirect_back fallback_location: admin_hosting_accounts_path, notice: result[:message]
    else
      redirect_back fallback_location: admin_hosting_accounts_path, alert: result[:message]
    end
  end

  private

  def set_hosting_account
    @hosting_account = HostingAccount.find(params[:id])
  end

  # 解析全手动 X 认证输入：整段回调 URL 或纯授权码 → [code, state]
  def parse_manual_auth_input(raw)
    return [nil, nil] if raw.blank?

    if raw.include?('code=')
      require 'uri'
      uri = URI.parse(raw)
      params = URI.decode_www_form(uri.query.to_s).to_h
      return [params['code'].to_s.presence, params['state'].to_s.presence]
    end

    [raw, nil]
  rescue
    [raw, nil]
  end

  def load_form_options
    @clients = Client.order(:name)
    @themes = Theme.order(:name).pluck(:name)
    @resource_queues = WorkMode.resource_modes.map { |m| [m.name, m.key] }
  end

  def hosting_account_params
    params.require(:hosting_account).permit(
      :client_id, :platform, :theme, :resource_queue, :publish_channel, :status, :remark
    )
  end
end
