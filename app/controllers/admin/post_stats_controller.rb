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

  # 导出当前筛选结果为 CSV
  def export
    @q = PostStat.ransack(params[:q])
    
    sort_column = params[:sort] || 'post_date'
    sort_direction = params[:direction] || 'desc'
    
    post_stats = @q.result(distinct: true)
                   .includes(:account)
                   .order(sort_column => sort_direction)
    
    # 生成 CSV 文件名
    filename = "发文数据统计_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv"
    
    # 设置响应头
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}"
    
    # 生成 CSV 内容
    csv_data = CSV.generate(encoding: 'utf-8') do |csv|
      # 表头
      csv << ['账号', '平台', '工作模式', '发文日期', '标题', '链接', '点赞数', '转发数', '评论数', '浏览数', '数据更新时间', '运营人员']
      
      # 数据行
      post_stats.each do |stat|
        csv << [
          stat.account&.account_name || '-',
          stat.account&.platform || '-',
          stat.account&.work_type || '-',
          stat.post_date&.strftime('%Y-%m-%d') || '-',
          stat.title || '-',
          stat.url || '-',
          stat.likes_count || 0,
          stat.shares_count || 0,
          stat.comments_count || 0,
          stat.views_count || 0,
          stat.data_updated_at&.strftime('%Y-%m-%d %H:%M') || '-',
          stat.account&.operator || '-'
        ]
      end
    end
    
    render plain: csv_data
  end
end