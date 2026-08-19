class Admin::MessageTemplatesController < Admin::BaseController
  before_action :set_template, only: [:edit, :update, :destroy]

  def index
    @q = MessageTemplate.ransack(params[:q])
    @templates = @q.result(distinct: true)
                   .order(:scenario, :language, :id)
                   .page(params[:page])
                   .per(20)
  end

  def new
    @template = MessageTemplate.new
  end

  def create
    @template = MessageTemplate.new(template_params)
    if @template.save
      redirect_to admin_message_templates_path, notice: "消息模板已创建"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      redirect_to admin_message_templates_path, notice: "消息模板已更新"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to admin_message_templates_path, notice: "消息模板已删除"
  end

  private

  def set_template
    @template = MessageTemplate.find(params[:id])
  end

  def template_params
    params.require(:message_template).permit(:name, :scenario, :language, :content)
  end
end
