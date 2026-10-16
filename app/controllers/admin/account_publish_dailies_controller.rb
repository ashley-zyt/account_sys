class Admin::AccountPublishDailiesController < Admin::BaseController
  RESULT_LABELS = {
    'success'          => '发布成功',
    'failed'           => '发布失败',
    'agent'            => 'agent外部',
    'banned'           => '账号封禁',
    'tiktok_low_views' => 'TikTok低浏览',
    'no_resource'      => '资源不足',
    'no_browser'       => '无浏览器',
    'unpublished'      => '未发布(待核查)'
  }.freeze

  # 发布对账页面：按日期查看每个账号当天的发布结果 + 未发布原因
  def index
    @stat_date = parse_date(params[:stat_date]) || AccountPublishDaily.maximum(:stat_date) || Date.today
    @result_filter = params[:result].presence
    @platform_filter = params[:platform].presence

    scope = AccountPublishDaily.where(stat_date: @stat_date)
    scope = scope.where(result: @result_filter) if @result_filter.present?
    scope = scope.where(platform: @platform_filter) if @platform_filter.present?

    @records = scope.includes(:account).order(:platform, :account_id)

    # 汇总 + 可用日期（供日期下拉）
    @summary = AccountPublishDaily.where(stat_date: @stat_date).group(:result).count
    @total_count = AccountPublishDaily.where(stat_date: @stat_date).count
    @available_dates = AccountPublishDaily.distinct.order(stat_date: :desc).limit(30).pluck(:stat_date)

    @result_options = AccountPublishDaily.results.keys
    @platform_options = Account.platforms.keys
  end

  private

  def parse_date(str)
    Date.parse(str)
  rescue ArgumentError, TypeError
    nil
  end
end
