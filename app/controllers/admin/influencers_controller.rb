class Admin::InfluencersController < Admin::BaseController
  before_action :set_influencer, only: [:edit, :update, :destroy]

  def index
    @q = Influencer.ransack(params[:q])
    @influencers = @q.result.includes(:domain).order(created_at: :desc).page(params[:page])
    @domains = Domain.order(:name)
  end

  def new
    @influencer = Influencer.new(enabled: true)
    @domains = Domain.order(:name)
  end

  def create
    @influencer = Influencer.new(influencer_params)
    if @influencer.save
      redirect_to admin_influencers_path, notice: '大V 已添加'
    else
      @domains = Domain.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @domains = Domain.order(:name)
  end

  def update
    if @influencer.update(influencer_params)
      redirect_to admin_influencers_path, notice: '大V 已更新'
    else
      @domains = Domain.order(:name)
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
    params.require(:influencer).permit(:username, :user_id, :platform, :domain_id, :enabled, :remark)
  end
end
