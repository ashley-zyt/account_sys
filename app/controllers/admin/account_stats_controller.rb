class Admin::AccountStatsController < Admin::BaseController
  # 账号总量快照统计（account_stats 日快照表）
  # 维度：每个账号的「最新一条」快照（从 post_stats 聚合 + 采集端返回的粉丝/点赞总量）
  # 用于横向对比：哪些账号表现好、哪个主题/平台粉丝增长快。
  def index
    # --- 筛选：默认只看「正常」状态账号的最新快照 ---
    params[:q] ||= {}

    # 1) 先获取每个账号的最新一条快照日期（窗口函数法，兼容 MySQL）
    latest_subquery = AccountStat
                        .select('account_id, MAX(stat_date) AS latest_date')
                        .group(:account_id)
                        .to_sql

    # 2) 每个账号最新快照 + 账号信息（平台/主题/工作模式/状态）
    base = AccountStat
              .joins("INNER JOIN (#{latest_subquery}) AS _latest ON _latest.account_id = account_stats.account_id AND _latest.latest_date = account_stats.stat_date")
              .joins(:account)
              .includes(account: :browser)

    # 3) ransack 仅支持账号维度过滤（对 account_stats 字段 ransack 会和 joins 冲突，单独在 where 层拼接）
    @q = Account.ransack(params[:q])
    account_conditions = @q.result.select(:id)
    base = base.where('account_stats.account_id IN (?)', account_conditions)

    # 4) 汇总 KPI（所有账号最新快照的加总 / 计数）
    rows = base.to_a
    @summary = {
      account_count:       rows.size,
      total_followers:     rows.sum { |r| r.followers_count.to_i },
      total_views_count:   rows.sum { |r| r.total_views_count.to_i },
      total_likes_count:   rows.sum { |r| r.total_likes_count.to_i },
      total_comments_count: rows.sum { |r| r.total_comments_count.to_i },
      total_shares_count:  rows.sum { |r| r.total_shares_count.to_i },
      total_posts_count:   rows.sum { |r| r.total_posts_count.to_i }
    }

    # 5) 按平台聚合（饼图 + 排行榜用）
    @by_platform = rows.group_by { |r| r.account.platform }
                            .map do |platform, list|
      {
        platform: platform,
        account_count:   list.size,
        followers:       list.sum { |r| r.followers_count.to_i },
        views:           list.sum { |r| r.total_views_count.to_i },
        likes:           list.sum { |r| r.total_likes_count.to_i },
        comments:        list.sum { |r| r.total_comments_count.to_i },
        shares:          list.sum { |r| r.total_shares_count.to_i },
        posts:           list.sum { |r| r.total_posts_count.to_i }
      }
    end.sort_by { |x| -x[:views] }

    # 6) 按主题聚合（排行榜用）
    @by_theme = rows.group_by { |r| r.account.theme }
                         .map do |theme, list|
      {
        theme: theme,
        account_count: list.size,
        followers:     list.sum { |r| r.followers_count.to_i },
        views:         list.sum { |r| r.total_views_count.to_i },
        likes:         list.sum { |r| r.total_likes_count.to_i },
        posts:         list.sum { |r| r.total_posts_count.to_i }
      }
    end.sort_by { |x| -x[:views] }

    # 7) 每个账号最新快照的明细（用于列表，支持按指标排序 + 分页）
    sort_column = %w[followers_count total_views_count total_likes_count total_comments_count total_shares_count total_posts_count stat_date].include?(params[:sort]) ? params[:sort] : 'total_views_count'
    sort_direction = params[:direction] == 'asc' ? 'asc' : 'desc'

    @account_stats = base.order("account_stats.#{sort_column} #{sort_direction}")
                             .page(params[:page])
                             .per(15)

    # 8) 筛选选项（下拉）
    @work_types = Account.work_types.map { |k, v| [k, v] }
    @platforms  = Account.platforms.map { |k, v| [k, v] }
    @themes     = Theme.pluck(:name)
    @statuses   = Account.statuses.keys

    @current_sort      = sort_column
    @current_direction = sort_direction
  end

  # 导出当前筛选的账号快照清单为 CSV
  def export
    params[:q] ||= {}
    @q = Account.ransack(params[:q])
    account_conditions = @q.result.select(:id)

    latest_subquery = AccountStat
                        .select('account_id, MAX(stat_date) AS latest_date')
                        .group(:account_id)
                        .to_sql

    rows = AccountStat
             .joins("INNER JOIN (#{latest_subquery}) AS _latest ON _latest.account_id = account_stats.account_id AND _latest.latest_date = account_stats.stat_date")
             .joins(account: :browser)
             .includes(account: :browser)
             .where('account_stats.account_id IN (?)', account_conditions)
             .order('account_stats.total_views_count DESC')
             .to_a

    require 'csv'
    filename = "账号数据统计_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv"
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}"

    csv_data = CSV.generate(encoding: 'utf-8') do |csv|
      csv << ['账号名', '主题', '平台', '工作模式', '账号状态', '绑定浏览器', '粉丝数', '总浏览', '总点赞', '总评论', '总转发', '总发帖', '快照日期', '账号主页']
      rows.each do |s|
        a = s.account
        csv << [
          a.account_name,
          a.theme,
          a.platform,
          a.work_type,
          a.status,
          a.browser&.profile_name || '-',
          s.followers_count.to_i,
          s.total_views_count.to_i,
          s.total_likes_count.to_i,
          s.total_comments_count.to_i,
          s.total_shares_count.to_i,
          s.total_posts_count.to_i,
          s.stat_date.strftime('%Y-%m-%d'),
          a.source_url || '-'
        ]
      end
    end
    csv_data = "\xEF\xBB\xBF" + csv_data
    render plain: csv_data
  end
end
