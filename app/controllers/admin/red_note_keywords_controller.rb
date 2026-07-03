class Admin::RedNoteKeywordsController < Admin::BaseController
  before_action :set_themes, only: [:index, :new, :create, :edit, :update]

  def index
    @q = RedNoteKeyword.ransack(params[:q])
    @red_note_keywords = @q.result
                            .order(created_at: :desc)
                            .page(params[:page])
  end

  def new
    @red_note_keyword = RedNoteKeyword.new
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

    created = []
    failed = []

    lines.each do |line|
      keyword, keyword_code = parse_keyword_line(line)
      next unless keyword && keyword_code

      kw = RedNoteKeyword.new(theme: theme, keyword: keyword, keyword_code: keyword_code)
      if kw.save
        created << kw
      else
        failed << { line: line, error: kw.errors.full_messages.join(", ") }
      end
    end

    if created.any?
      flash[:notice] = "成功添加 #{created.size} 个关键词" + (failed.any? ? "（#{failed.size} 个失败）" : "")
    else
      flash[:alert] = "关键词添加失败：#{failed.first&.dig(:error) || '未知错误'}"
    end

    redirect_to admin_red_note_keywords_path
  rescue => e
    Rails.logger.error "[RedNoteKeywords] 批量添加失败: #{e.message}"
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  def show
    @red_note_keyword = RedNoteKeyword.find(params[:id])
    render layout: false if request.xhr?
  end

  def edit
    @red_note_keyword = RedNoteKeyword.find(params[:id])
    render layout: false if request.xhr?
  end

  def update
    @red_note_keyword = RedNoteKeyword.find(params[:id])
    if @red_note_keyword.update(red_note_keyword_params)
      redirect_to admin_red_note_keywords_path, notice: "关键词更新成功"
    else
      @themes = Theme.pluck(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @red_note_keyword = RedNoteKeyword.find(params[:id])
    @red_note_keyword.destroy
    redirect_to admin_red_note_keywords_path, notice: "关键词删除成功"
  end

  # POST /admin/red_note_keywords/:id/create_task
  def create_task
    @red_note_keyword = RedNoteKeyword.find(params[:id])
    if @red_note_keyword.status == 1 # 待执行
      success = RedNoteApiService.fetch_token && RedNoteApiService.create_task(@red_note_keyword)
    else
      success = RedNoteApiService.create_task(@red_note_keyword)
    end

    if success
      redirect_to admin_red_note_keywords_path, notice: "任务创建成功"
    else
      redirect_to admin_red_note_keywords_path, alert: "任务创建失败，请检查远程服务"
    end
  end

  # POST /admin/red_note_keywords/batch_create_task
  def batch_create_task
    keyword_ids = params[:keyword_ids]
    keywords = RedNoteKeyword.where(id: keyword_ids, status: [0]) # 未启动

    success_count = 0
    keywords.each do |kw|
      success_count += 1 if RedNoteApiService.create_task(kw)
    end

    redirect_to admin_red_note_keywords_path,
                notice: "批量创建任务完成：成功 #{success_count}/#{keywords.size}"
  end

  # POST /admin/red_note_keywords/sync_status
  def sync_status
    RedNoteApiService.sync_all_pending
    redirect_to admin_red_note_keywords_path, notice: "状态同步完成"
  end

  private

  def set_themes
    @themes = Theme.pluck(:name)
  end

  def red_note_keyword_params
    params.require(:red_note_keyword).permit(:theme, :keyword, :keyword_code)
  end

  # 解析关键词行，支持 "关键词 编码"（空格分割）或 "关键词/编码"（斜杠分割）
  def parse_keyword_line(line)
    # 先尝试空格分割
    parts = line.split(/\s+/)
    if parts.size >= 2
      keyword_code = parts.pop
      keyword = parts.join(" ")
      return [keyword.strip, keyword_code.strip]
    end

    # 再尝试斜杠分割
    parts = line.split("/")
    if parts.size >= 2
      keyword_code = parts.pop
      keyword = parts.join("/")
      return [keyword.strip, keyword_code.strip]
    end

    [nil, nil]
  end
end
