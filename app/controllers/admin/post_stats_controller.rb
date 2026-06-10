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
    @work_types = Account.work_types.invert  # 获取工作模式选项
    @platforms = Account.platforms.invert    # 获取平台选项
    
    @current_sort = sort_column
    @current_direction = sort_direction
  end
end