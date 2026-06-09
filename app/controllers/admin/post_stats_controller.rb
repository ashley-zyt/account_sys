class Admin::PostStatsController < Admin::BaseController
  def index
    @q = PostStat.ransack(params[:q])
    
    sort_column = params[:sort] || 'post_date'
    sort_direction = params[:direction] || 'desc'
    
    @post_stats = @q.result(distinct: true)
                   .includes(:account)
                   .order(sort_column => sort_direction)
                   .page(params[:page])
                   .per(15)
    @accounts = Account.all
    
    @current_sort = sort_column
    @current_direction = sort_direction
  end
end