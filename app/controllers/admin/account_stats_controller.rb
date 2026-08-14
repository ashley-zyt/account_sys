class Admin::AccountStatsController < Admin::BaseController
  # 账号总量快照统计（account_stats 日快照表）
  # 核心功能：每个账号最新累计快照 + 粉丝变化趋势（日增/7日增/30日走势图）
  def index
    params[:q] ||= {}
    # 清除空字符串参数，避免 ransack 用空字符串过滤返回空结果
    params[:q].reject! { |_, v| v.blank? }

    # 1) 获取筛选范围内的账号ID集合
    @q = Account.ransack(params[:q])
    filtered_accounts = @q.result(distinct: true)
    account_ids = filtered_accounts.pluck(:id)

    # 无账号时直接返回空数据
    if account_ids.empty?
      @summary = empty_summary
      @overall_trend = { labels: [], data: [] }
      @top5_title = "Top5 账号增长对比"
      @top5_trend = { labels: [], datasets: [] }
      @account_stats = Kaminari.paginate_array([]).page(params[:page]).per(15)
      @by_platform = []
      @by_theme = []
      set_filter_options
      @current_sort = 'followers_count'
      @current_direction = 'desc'
      return
    end

    today = Date.today
    date_30 = today - 29  # 近30天（含今天）

    # 2) 一次性加载筛选范围内所有账号近30天的快照（用于趋势计算和sparkline）
    all_stats = AccountStat
                  .where(account_id: account_ids)
                  .where('stat_date >= ?', date_30)
                  .order(account_id: :asc, stat_date: :asc)
                  .to_a

    # 按 account_id 分组: { account_id => [AccountStat, ...] (按日期升序) }
    stats_by_account = all_stats.group_by(&:account_id)

    # 3) 获取每个账号的最新快照
    latest_stats = stats_by_account.map { |aid, stats| stats.last }.compact
    # 对没有快照记录的账号，不展示
    latest_stats = latest_stats.select { |s| s.account.present? }

    # 4) 计算每个账号的增量指标：日增/7日增/30日增 + sparkline数据
    account_data_map = {}
    latest_stats.each do |stat|
      aid = stat.account_id
      history = stats_by_account[aid] || []
      history_by_date = history.index_by(&:stat_date)

      # 取1天前、7天前、30天前的粉丝数（找最接近的那天，不一定刚好有记录）
      followers_today = stat.followers_count.to_i
      followers_yesterday = find_followers_on(history_by_date, today - 1)
      followers_7d_ago  = find_followers_on(history_by_date, today - 7)
      followers_30d_ago = find_followers_on(history_by_date, date_30)

      daily_growth = followers_yesterday ? followers_today - followers_yesterday : nil
      weekly_growth = followers_7d_ago ? followers_today - followers_7d_ago : nil
      monthly_growth = followers_30d_ago ? followers_today - followers_30d_ago : nil

      # sparkline: 近30天粉丝数，缺失的日期用前一天的值填充（forward fill）
      sparkline = build_sparkline(history_by_date, date_30, today)

      account_data_map[aid] = {
        stat: stat,
        daily_growth: daily_growth,
        weekly_growth: weekly_growth,
        monthly_growth: monthly_growth,
        sparkline: sparkline
      }
    end

    # 5) 汇总 KPI
    total_followers_today = latest_stats.sum { |s| s.followers_count.to_i }
    total_followers_yesterday = latest_stats.sum { |s|
      d = account_data_map[s.account_id]
      d && d[:daily_growth] ? s.followers_count.to_i - d[:daily_growth] : s.followers_count.to_i
    }
    total_followers_7d_ago = latest_stats.sum { |s|
      d = account_data_map[s.account_id]
      d && d[:weekly_growth] ? s.followers_count.to_i - d[:weekly_growth] : s.followers_count.to_i
    }
    daily_growth_total = total_followers_today - total_followers_yesterday
    weekly_growth_total = total_followers_today - total_followers_7d_ago

    # 增长/下跌账号统计
    growing_accounts = account_data_map.values.count { |d| d[:daily_growth] && d[:daily_growth] > 0 }
    declining_accounts = account_data_map.values.count { |d| d[:daily_growth] && d[:daily_growth] < 0 }

    # 按主题7日增长排名，取Top1
    theme_7d_growth = latest_stats.group_by { |s| s.account.theme }.map { |theme, list|
      growth = list.sum { |s| (account_data_map[s.account_id] || {})[:weekly_growth] || 0 }
      { theme: theme, growth: growth, followers: list.sum { |s| s.followers_count.to_i } }
    }.sort_by { |x| -x[:growth] }

    top_theme = theme_7d_growth.first

    weekly_pct = total_followers_7d_ago > 0 ? (weekly_growth_total.to_f / total_followers_7d_ago * 100).round(1) : nil

    @summary = {
      account_count:       latest_stats.size,
      total_followers:     total_followers_today,
      daily_growth:        daily_growth_total,
      weekly_growth:       weekly_growth_total,
      weekly_pct:          weekly_pct,
      growing_accounts:    growing_accounts,
      declining_accounts:  declining_accounts,
      flat_accounts:       latest_stats.size - growing_accounts - declining_accounts,
      top_theme:           top_theme,
      total_views:         latest_stats.sum { |s| s.total_views_count.to_i },
      total_likes:         latest_stats.sum { |s| s.total_likes_count.to_i },
      total_posts:         latest_stats.sum { |s| s.total_posts_count.to_i }
    }

    # 6) 整体趋势：近30天全账号粉丝总量
    # 按日期聚合所有账号粉丝数（同一天所有有记录的账号的粉丝数之和）
    daily_totals = {}
    (date_30..today).each { |d| daily_totals[d] = 0 }
    all_stats.each do |s|
      next if s.stat_date < date_30
      daily_totals[s.stat_date] ||= 0
      daily_totals[s.stat_date] += s.followers_count.to_i
    end
    # forward fill: 某天没有记录的账号，用前一天的值（近似）
    sorted_dates = daily_totals.keys.sort
    prev_total = nil
    sorted_dates.each do |d|
      if daily_totals[d] == 0 && prev_total
        daily_totals[d] = prev_total
      end
      prev_total = daily_totals[d] if daily_totals[d] > 0
    end
    @overall_trend = {
      labels: sorted_dates.map { |d| d.strftime('%-m/%-d') },
      data: sorted_dates.map { |d| daily_totals[d] }
    }

    # 7) Top5 账号增长对比（近30天，按30日增长取Top5）
    # 动态标题：筛选了平台则显示单平台Top5，否则显示全平台Top5
    selected_platform = params.dig(:q, :platform_eq)
    @top5_title = if selected_platform.present?
                    platform_label = Account.platforms.key(selected_platform.to_i) || selected_platform
                    "#{platform_label.to_s.titleize} Top5 账号增长对比"
                  else
                    "全平台 Top5 账号增长对比"
                  end

    # 平台颜色映射（与视图中表格标签颜色一致）
    platform_colors = {
      'facebook'  => '#3b82f6',
      'twitter'   => '#06b6d4',
      'tiktok'    => '#ec4899',
      'youtube'   => '#ef4444',
      'instagram' => '#a855f7'
    }
    fallback_colors = ['#6366f1', '#22c55e', '#f59e0b', '#14b8a6', '#f97316']

    top5_ids = account_data_map.values
                  .sort_by { |d| -(d[:monthly_growth] || -999999) }
                  .first(5)
                  .map { |d| d[:stat].account_id }
    top5_datasets = []
    top5_ids.each_with_index do |aid, i|
      d = account_data_map[aid]
      next unless d
      account = d[:stat].account
      # 优先用平台颜色，平台颜色不够时用备选颜色
      color = platform_colors[account.platform] || fallback_colors[i % fallback_colors.length]
      top5_datasets << {
        label: "#{account.account_name} (#{account.platform})",
        data: d[:sparkline],
        borderColor: color,
        backgroundColor: 'transparent',
        platform: account.platform
      }
    end
    @top5_trend = {
      labels: sorted_dates.map { |d| d.strftime('%-m/%-d') },
      datasets: top5_datasets
    }

    # 8) 按平台聚合
    @by_platform = latest_stats.group_by { |r| r.account.platform }.map { |platform, list|
      growth_7d = list.sum { |s| (account_data_map[s.account_id] || {})[:weekly_growth] || 0 }
      {
        platform: platform,
        account_count: list.size,
        followers: list.sum { |s| s.followers_count.to_i },
        growth_7d: growth_7d,
        views: list.sum { |s| s.total_views_count.to_i }
      }
    }.sort_by { |x| -x[:followers] }

    # 9) 按主题聚合
    @by_theme = latest_stats.group_by { |r| r.account.theme }.map { |theme, list|
      growth_7d = list.sum { |s| (account_data_map[s.account_id] || {})[:weekly_growth] || 0 }
      {
        theme: theme,
        account_count: list.size,
        followers: list.sum { |s| s.followers_count.to_i },
        growth_7d: growth_7d,
        views: list.sum { |s| s.total_views_count.to_i }
      }
    }.sort_by { |x| -x[:growth_7d] }

    # 10) 账号明细列表：支持排序
    sort_column = params[:sort]
    sort_direction = params[:direction] == 'asc' ? 'asc' : 'desc'

    # 可排序列映射（含新增的增长列）
    valid_sorts = %w[followers_count total_views_count total_likes_count total_comments_count total_shares_count total_posts_count stat_date daily_growth weekly_growth]
    sort_column = valid_sorts.include?(sort_column) ? sort_column : 'followers_count'

    # 对内存中的数据排序
    sorted_data = account_data_map.values.sort_by { |d|
      val = case sort_column
            when 'daily_growth' then d[:daily_growth] || -999999999
            when 'weekly_growth' then d[:weekly_growth] || -999999999
            when 'stat_date' then d[:stat].stat_date.to_time.to_i
            else d[:stat].send(sort_column).to_i
            end
      val
    }
    sorted_data.reverse! if sort_direction == 'desc'

    # Kaminari 分页（对数组分页）
    per_page = 15
    page = (params[:page] || 1).to_i
    total = sorted_data.size
    offset = (page - 1) * per_page
    paged_data = sorted_data[offset, per_page] || []

    @account_stats = Kaminari.paginate_array(sorted_data.map { |d| d[:stat] }, total_count: total)
                             .page(page)
                             .per(per_page)
    # 把增量数据和sparkline传给视图
    @account_growth_map = {}
    @account_sparklines = {}
    paged_data.each do |d|
      aid = d[:stat].account_id
      @account_growth_map[aid] = {
        daily: d[:daily_growth],
        weekly: d[:weekly_growth],
        monthly: d[:monthly_growth]
      }
      @account_sparklines[aid] = d[:sparkline]
    end

    set_filter_options
    @current_sort = sort_column
    @current_direction = sort_direction
  end

  # 导出当前筛选的账号快照清单为 CSV
  def export
    params[:q] ||= {}
    params[:q].reject! { |_, v| v.blank? }
    @q = Account.ransack(params[:q])
    account_ids = @q.result(distinct: true).pluck(:id)

    today = Date.today
    date_30 = today - 29

    all_stats = AccountStat
                  .where(account_id: account_ids)
                  .where('stat_date >= ?', date_30)
                  .order(account_id: :asc, stat_date: :asc)
                  .to_a
    stats_by_account = all_stats.group_by(&:account_id)

    latest_subquery = AccountStat
                        .select('account_id, MAX(stat_date) AS latest_date')
                        .where(account_id: account_ids)
                        .group(:account_id)
                        .to_sql

    rows = AccountStat
             .joins("INNER JOIN (#{latest_subquery}) AS _latest ON _latest.account_id = account_stats.account_id AND _latest.latest_date = account_stats.stat_date")
             .joins(account: :browser)
             .includes(account: :browser)
             .where('account_stats.account_id IN (?)', account_ids)
             .order('account_stats.followers_count DESC')
             .to_a

    require 'csv'
    filename = "账号数据统计_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv"
    response.headers['Content-Type'] = 'text/csv; charset=utf-8'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}"

    csv_data = CSV.generate(encoding: 'utf-8') do |csv|
      csv << ['账号名', '主题', '平台', '工作模式', '账号状态', '粉丝数', '日增粉丝', '7日增粉', '总浏览', '总点赞', '总发帖', '快照日期', '账号主页']
      rows.each do |s|
        a = s.account
        history = stats_by_account[a.id] || []
        history_by_date = history.index_by(&:stat_date)
        fy = find_followers_on(history_by_date, today - 1)
        f7 = find_followers_on(history_by_date, today - 7)
        daily = fy ? s.followers_count.to_i - fy : nil
        weekly = f7 ? s.followers_count.to_i - f7 : nil
        csv << [
          a.account_name,
          a.theme,
          a.platform,
          a.work_type,
          a.status,
          s.followers_count.to_i,
          daily || '-',
          weekly || '-',
          s.total_views_count.to_i,
          s.total_likes_count.to_i,
          s.total_posts_count.to_i,
          s.stat_date.strftime('%Y-%m-%d'),
          a.source_url || '-'
        ]
      end
    end
    csv_data = "\xEF\xBB\xBF" + csv_data
    render plain: csv_data
  end

  private

  def set_filter_options
    @work_types = Account.work_types.map { |k, v| [k, v] }
    @platforms  = Account.platforms.map { |k, v| [k.to_s.titleize, v] }
    @themes     = Theme.pluck(:name)
    @statuses   = Account.statuses.map { |k, v| [k, v] }
  end

  def empty_summary
    {
      account_count: 0, total_followers: 0, daily_growth: 0, weekly_growth: 0,
      weekly_pct: nil, growing_accounts: 0, declining_accounts: 0, flat_accounts: 0,
      top_theme: nil, total_views: 0, total_likes: 0, total_posts: 0
    }
  end

  # 在历史记录中找到指定日期的粉丝数，如果那天没有记录，向前找最近的有记录的天
  def find_followers_on(history_by_date, date)
    # 最多向前找7天
    0.upto(7) do |offset|
      d = date - offset
      record = history_by_date[d]
      return record.followers_count.to_i if record
    end
    nil
  end

  # 构建近30天sparkline数组，缺失日期用前一天的值forward fill
  def build_sparkline(history_by_date, start_date, end_date)
    result = []
    last_value = nil
    (start_date..end_date).each do |d|
      record = history_by_date[d]
      if record
        last_value = record.followers_count.to_i
        result << last_value
      elsif last_value
        result << last_value
      else
        result << nil
      end
    end
    # 开头的nil用第一个有效值填充
    first_valid = result.compact.first
    if first_valid
      result.map! { |v| v.nil? ? first_valid : v }
    else
      result.map! { |v| v || 0 }
    end
    result
  end
end
