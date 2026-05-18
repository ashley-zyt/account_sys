class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [:show, :edit, :update, :initiate_contact, :start_conversation]

  def index
    @q = Kol.ransack(params[:q])
    @kols = @q.result(distinct: true)
             .order(created_at: :desc)
             .page(params[:page])
             .per(10)

    @categories = Kol.pluck(:category).compact.uniq
    @locations = Kol.pluck(:location).compact.uniq
  end

  def show
    @platform_accounts = @kol.kol_platform_accounts.includes(:conversations)
    @conversations = @kol.conversations.includes(:kol_platform_account).order(created_at: :desc)

    @accounts = Account.all
    @templates = MessageTemplate.all
  end

  def new
    @kol = Kol.new
    @kol.kol_platform_accounts.build
  end

  def create
    @kol = Kol.new(kol_params)
    if @kol.save
      redirect_to admin_kol_path(@kol), notice: "KOL已成功创建"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @kol.update(kol_params)
      redirect_to admin_kol_path(@kol), notice: "KOL信息已更新"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def initiate_contact
    @accounts = Account.all
    @templates = MessageTemplate.all
    @platform_accounts = @kol.kol_platform_accounts
    render layout: false
  end

  def start_conversation
    account = Account.find(params[:account_id])
    template = MessageTemplate.find(params[:template_id])
    kol_platform_account = KolPlatformAccount.find(params[:kol_platform_account_id])

    conversation = Conversation.create!(
      kol: @kol,
      kol_platform_account: kol_platform_account,
      account: account,
      platform: kol_platform_account.platform,
      status: :pending,
      latest_message: template.content.truncate(100)
    )

    redirect_to admin_kol_path(@kol), notice: "已成功发起会话"
  rescue ActiveRecord::RecordNotFound => e
    redirect_to admin_kol_path(@kol), alert: "创建会话失败：#{e.message}"
  end

  private

  def set_kol
    @kol = Kol.find(params[:id])
  end

  def kol_params
    params.require(:kol).permit(
      :kol_name,
      :nick_name,
      :location,
      :category,
      :notes,
      kol_platform_accounts_attributes: [:id, :platform, :nick_name, :profile_url, :follower_count, :_destroy]
    )
  end
end