class Admin::ThemesController < Admin::BaseController
  before_action :set_theme, only: [:edit, :update, :destroy]

  def index
    @themes = Theme.order(created_at: :desc).page(params[:page]).per(10)
    @theme = Theme.new
  end

  def edit
  end

  def create
    @theme = Theme.new(theme_params)

    respond_to do |format|
      if @theme.save
        format.html { redirect_to admin_themes_path, notice: '主题创建成功' }
        format.json { render json: { success: true, message: '主题创建成功' } }
      else
        format.html { redirect_to admin_themes_path, alert: @theme.errors.full_messages.join(', ') }
        format.json { render json: { success: false, message: @theme.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @theme.update(theme_params)
        format.html { redirect_to admin_themes_path, notice: '主题更新成功' }
        format.json { render json: { success: true, message: '主题更新成功' } }
      else
        format.html { redirect_to admin_themes_path, alert: @theme.errors.full_messages.join(', ') }
        format.json { render json: { success: false, message: @theme.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @theme.destroy
    redirect_to admin_themes_path, notice: '主题删除成功'
  end

  def new_modal
    @theme = Theme.new
    render layout: false
  end

  def edit_modal
    @theme = Theme.find(params[:id])
    render layout: false
  end

  private

  def set_theme
    @theme = Theme.find(params[:id])
  end

  def theme_params
    params.require(:theme).permit(:name, :oss_directory, :titles, :remark)
  end
end
