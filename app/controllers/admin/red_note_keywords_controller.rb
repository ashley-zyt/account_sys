class Admin::RedNoteKeywordsController < Admin::BaseController
  before_action :set_themes, only: [:index, :new, :create, :edit, :update]

  def index
    @q = RedNoteKeyword.ransack(params[:q])
    @red_note_keywords = @q.result
                            .order(created_at: :desc)
                            .page(params[:page])
    @setting = RedNoteSetting.current
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
    existing_codes = RedNoteKeyword.pluck(:keyword_code)

    lines.each do |line|
      keyword, keyword_code = parse_keyword_line(line)
      unless keyword && keyword_code
        failed << { line: line, error: "格式错误，无法解析关键词和编码" }
        next
      end

      if existing_codes.include?(keyword_code)
        failed << { line: line, error: "编码 #{keyword_code} 已存在" }
        next
      end

      kw = RedNoteKeyword.new(theme: theme, keyword: keyword, keyword_code: keyword_code)
      if kw.save
        created << kw
        existing_codes << keyword_code
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
    success = RedNoteApiService.create_task(@red_note_keyword)

    if success
      redirect_to admin_red_note_keywords_path, notice: "任务创建成功"
    else
      redirect_to admin_red_note_keywords_path, alert: "任务创建失败，请查看日志或检查远程服务"
    end
  end

  # POST /admin/red_note_keywords/:id/sync_task
  def sync_task
    @red_note_keyword = RedNoteKeyword.find(params[:id])
    success = RedNoteApiService.sync_task_status(@red_note_keyword)

    if success
      redirect_to admin_red_note_keywords_path, notice: "任务同步成功"
    else
      redirect_to admin_red_note_keywords_path, alert: "任务同步失败，请查看日志或检查远程服务"
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

  # GET /admin/red_note_keywords/settings
  def settings
    @setting = RedNoteSetting.current
    render layout: false if request.xhr?
  end

  # PATCH /admin/red_note_keywords/settings
  def update_settings
    @setting = RedNoteSetting.current
    if @setting.update(setting_params)
      redirect_to admin_red_note_keywords_path, notice: "设置已更新"
    else
      flash[:alert] = @setting.errors.full_messages.join("；")
      redirect_to admin_red_note_keywords_path
    end
  end

  private

  def set_themes
    @themes = Theme.pluck(:name)
  end

  def red_note_keyword_params
    params.require(:red_note_keyword).permit(:theme, :keyword, :keyword_code)
  end

  def setting_params
    params.require(:red_note_setting).permit(:search_max_results, :top_n_by_likes)
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
