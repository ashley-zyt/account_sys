class Admin::CommentThemeConfigsController < Admin::BaseController
  before_action :set_config, only: [:edit, :update, :destroy]
  before_action :load_form_options, only: [:new, :create, :edit, :update]

  def index
    @configs = CommentThemeConfig.order(:theme).page(params[:page])
  end

  def new
    @config = CommentThemeConfig.new
  end

  def create
    @config = CommentThemeConfig.new(config_params)
    if @config.save
      redirect_to admin_comment_theme_configs_path, notice: '评论 Prompt 已添加'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @config.update(config_params)
      redirect_to admin_comment_theme_configs_path, notice: '评论 Prompt 已更新'
    else
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

  def load_form_options
    @themes = Theme.order(:name)
    # 已录入的主题 → prompt 映射，供前端选择主题后自动带入
    @existing_prompts = CommentThemeConfig.pluck(:theme, :prompt).to_h
  end

  def config_params
    params.require(:comment_theme_config).permit(:theme, :prompt)
  end
end
