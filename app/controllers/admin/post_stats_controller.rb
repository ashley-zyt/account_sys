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
    # 工作模式选项：[[显示文本, 数字值], ...]
    @work_types = Account.work_types.map { |k, v| [k, v] }
    # 平台选项：[[显示文本, 数字值], ...]
    @platforms = Account.platforms.map { |k, v| [k, v] }
    
    @current_sort = sort_column
    @current_direction = sort_direction
  end
end