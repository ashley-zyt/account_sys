class Admin::HuashengKeywordsController < Admin::BaseController
  before_action :set_themes, only: [:index, :new, :create, :edit, :update]

  def index
    @q = HuashengKeyword.ransack(params[:q])
    @huasheng_keywords = @q.result
                            .order(created_at: :desc)
                            .page(params[:page])
  end

  def new
    @huasheng_keyword = HuashengKeyword.new
    render :new, layout: false if request.xhr?
  end

  def create
    lines = params[:keywords_text].to_s.strip.lines.map(&:strip).reject(&:blank?)

    if lines.empty?
      render json: { success: false, error: "请输入至少一个关键词" }, status: :unprocessable_entity
      return
    end

    theme = params[:theme].to_s.strip
    if theme.blank?
      render json: { success: false, error: "请选择主题" }, status: :unprocessable_entity
      return
    end

    theme = theme.gsub("剪映-", "")

    created = []
    failed = []

    lines.each do |line|
      kw = HuashengKeyword.new(theme: theme, keyword: line)
      if kw.save
        created << kw
      else
        failed << { line: line, error: kw.errors.full_messages.join(", ") }
      end
    end

    if created.any?
      if failed.any?
        flash[:notice] = "成功添加 #{created.size} 个关键词"
        flash[:alert] = "#{failed.size} 个失败：#{failed.map { |f| f[:error] }.join('；')}"
      else
        flash[:notice] = "成功添加 #{created.size} 个关键词"
      end
    else
      flash[:alert] = "添加失败：#{failed.first&.dig(:error) || '未知错误'}"
    end

    redirect_to admin_huasheng_keywords_path
  rescue => e
    Rails.logger.error "[HuashengKeywords] 批量添加失败: #{e.message}"
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def show
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    render layout: false if request.xhr?
  end

  def edit
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    render layout: false if request.xhr?
  end

  def update
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    if @huasheng_keyword.update(huasheng_keyword_params)
      redirect_to admin_huasheng_keywords_path, notice: "关键词更新成功"
    else
      @themes = Theme.pluck(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @huasheng_keyword = HuashengKeyword.find(params[:id])
    unless @huasheng_keyword.status == 0
      redirect_to admin_huasheng_keywords_path, alert: "仅未启动的任务可以删除"
      return
    end
    @huasheng_keyword.destroy
    redirect_to admin_huasheng_keywords_path, notice: "关键词删除成功"
  end

  private

  def set_themes
    @themes = Theme.pluck(:name)
  end

  def huasheng_keyword_params
    params.require(:huasheng_keyword).permit(:theme, :keyword)
  end
end
