class Admin::PostStatsController < Admin::BaseController
  before_action :set_post_stat, only: [:show, :edit, :update, :destroy]

  def index
    @q = PostStat.ransack(params[:q])
    @post_stats = @q.result(distinct: true)
                   .includes(:account)
                   .order(post_date: :desc)
                   .page(params[:page])
                   .per(15)
    @accounts = Account.all
  end

  def new
    @post_stat = PostStat.new
    @accounts = Account.all
  end

  def create
    @post_stat = PostStat.new(post_stat_params)
    if @post_stat.save
      redirect_to admin_post_stats_path, notice: "发文数据已成功创建"
    else
      @accounts = Account.all
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @accounts = Account.all
  end

  def update
    if @post_stat.update(post_stat_params)
      redirect_to admin_post_stats_path, notice: "发文数据已更新"
    else
      @accounts = Account.all
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post_stat.destroy
    redirect_to admin_post_stats_path, notice: "发文数据已删除"
  end

  private

  def set_post_stat
    @post_stat = PostStat.find(params[:id])
  end

  def post_stat_params
    params.require(:post_stat).permit(
      :account_id,
      :post_date,
      :title,
      :url,
      :likes_count,
      :shares_count,
      :comments_count,
      :views_count,
      :data_updated_at
    )
  end
end