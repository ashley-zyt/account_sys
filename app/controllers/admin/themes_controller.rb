class Admin::ThemesController < Admin::BaseController
  before_action :set_theme, only: [:show, :edit, :update, :destroy]

  def index
    @themes = Theme.order(created_at: :desc).page(params[:page]).per(10)
  end

  def show
  end

  def new
    @theme = Theme.new
  end

  def edit
  end

  def create
    @theme = Theme.new(theme_params)

    if @theme.save
      redirect_to admin_themes_path, notice: '主题创建成功'
    else
      render :new
    end
  end

  def update
    if @theme.update(theme_params)
      redirect_to admin_themes_path, notice: '主题更新成功'
    else
      render :edit
    end
  end

  def destroy
    @theme.destroy
    redirect_to admin_themes_path, notice: '主题删除成功'
  end

  private

  def set_theme
    @theme = Theme.find(params[:id])
  end

  def theme_params
    params.require(:theme).permit(:name, :oss_directory, :titles, :remark)
  end
end
