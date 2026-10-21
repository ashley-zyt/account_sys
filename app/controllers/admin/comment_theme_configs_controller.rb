class Admin::CommentThemeConfigsController < Admin::BaseController
  before_action :set_config, only: [:edit, :update, :destroy]

  def index
    @configs = CommentThemeConfig.order(:theme).page(params[:page])
  end

  def new
    @config = CommentThemeConfig.new
    @themes = Theme.order(:name)
  end

  def create
    @config = CommentThemeConfig.new(config_params)
    if @config.save
      redirect_to admin_comment_theme_configs_path, notice: '评论 Prompt 已添加'
    else
      @themes = Theme.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @themes = Theme.order(:name)
  end

  def update
    if @config.update(config_params)
      redirect_to admin_comment_theme_configs_path, notice: '评论 Prompt 已更新'
    else
      @themes = Theme.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @config.destroy
    redirect_to admin_comment_theme_configs_path, notice: '评论 Prompt 已删除'
  end

  private

  def set_config
    @config = CommentThemeConfig.find(params[:id])
  end

  def config_params
    params.require(:comment_theme_config).permit(:theme, :prompt)
  end
end
