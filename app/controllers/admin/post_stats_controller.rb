class Admin::PostStatsController < Admin::BaseController
  def index
    @q = PostStat.ransack(params[:q])
    @post_stats = @q.result(distinct: true)
                   .includes(:account)
                   .order(post_date: :desc)
                   .page(params[:page])
                   .per(15)
    @accounts = Account.all
  end
end