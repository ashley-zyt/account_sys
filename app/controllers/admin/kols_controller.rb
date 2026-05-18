class Admin::KolsController < Admin::BaseController
  before_action :set_kol, only: [:show, :edit, :update]

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
      :notes
    )
  end
end