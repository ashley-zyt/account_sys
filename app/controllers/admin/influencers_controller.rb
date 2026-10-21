class Admin::InfluencersController < Admin::BaseController
  before_action :set_influencer, only: [:edit, :update, :destroy]

  def index
    @q = Influencer.ransack(params[:q])
    @influencers = @q.result.order(enabled: :desc, created_at: :desc).page(params[:page])
    @themes = Theme.order(:name)
  end

  def new
    @influencer = Influencer.new(enabled: true)
    @themes = Theme.order(:name)
  end

  def create
    @influencer = Influencer.new(influencer_params)
    if @influencer.save
      redirect_to admin_influencers_path, notice: '大V 已添加'
    else
      @themes = Theme.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @themes = Theme.order(:name)
  end

  def update
    if @influencer.update(influencer_params)
      redirect_to admin_influencers_path, notice: '大V 已更新'
    else
      @themes = Theme.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @influencer.destroy
    redirect_to admin_influencers_path, notice: '大V 已删除'
  end

  private

  def set_influencer
    @influencer = Influencer.find(params[:id])
  end

  def influencer_params
    params.require(:influencer).permit(:username, :user_id, :platform, :account_url, :theme, :enabled, :remark)
  end
end
