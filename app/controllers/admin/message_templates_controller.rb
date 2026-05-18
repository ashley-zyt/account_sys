class Admin::MessageTemplatesController < Admin::BaseController
  before_action :set_message_template, only: [:edit, :update, :destroy]

  def index
    @q = MessageTemplate.ransack(params[:q])
    @templates = @q.result(distinct: true)
                   .order(created_at: :desc)
                   .page(params[:page])
                   .per(10)

    @platforms = MessageTemplate.platforms.keys
    @template_types = MessageTemplate.template_types.keys
    @languages = MessageTemplate.pluck(:language).compact.uniq
  end

  def new
    @template = MessageTemplate.new
    @platforms = MessageTemplate.platforms
    @template_types = MessageTemplate.template_types
  end

  def create
    @template = MessageTemplate.new(message_template_params)
    if @template.save
      redirect_to admin_message_templates_path, notice: "模板已成功创建"
    else
      @platforms = MessageTemplate.platforms
      @template_types = MessageTemplate.template_types
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @platforms = MessageTemplate.platforms
    @template_types = MessageTemplate.template_types
  end

  def update
    if @template.update(message_template_params)
      redirect_to admin_message_templates_path, notice: "模板已更新"
    else
      @platforms = MessageTemplate.platforms
      @template_types = MessageTemplate.template_types
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to admin_message_templates_path, notice: "模板已删除"
  end

  private

  def set_message_template
    @template = MessageTemplate.find(params[:id])
  end

  def message_template_params
    params.require(:message_template).permit(
      :platform,
      :template_type,
      :language,
      :content
    )
  end
end