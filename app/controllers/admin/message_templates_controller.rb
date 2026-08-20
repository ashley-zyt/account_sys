class Admin::MessageTemplatesController < Admin::BaseController
  before_action :set_template, only: [:edit, :update, :destroy]
  before_action :load_dictionaries, only: [:index, :new, :create, :edit, :update]

  def index
    @q = MessageTemplate.ransack(params[:q])
    @templates = @q.result(distinct: true)
                   .includes(:domain, :message_template_versions, :message_variables)
                   .order(:scenario, :id)
                   .page(params[:page])
                   .per(20)
  end

  def new
    @template = MessageTemplate.new
    @template.message_template_versions.build
  end

  def create
    @template = MessageTemplate.new(template_params)
    if @template.save
      @template.update(message_variable_ids: params[:message_variable_ids] || [])
      redirect_to admin_message_templates_path, notice: "消息模板已创建"
    else
      @template.message_template_versions.build if @template.message_template_versions.empty?
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      @template.update(message_variable_ids: params[:message_variable_ids] || [])
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

  def load_dictionaries
    @domains = Domain.order(:name)
    @languages = Language.order(:id)
    @message_variables = MessageVariable.order(:id)
  end

  def template_params
    p = params.require(:message_template).permit(
      :name, :scenario, :platform, :domain_id,
      message_template_versions_attributes: [
        :id, :language_id, :content, :_destroy
      ]
    )
    # 平台为空（"通用"）时置 nil，避免 enum 解析空字符串报错
    p[:platform] = nil if p[:platform].blank?
    p
  end
end
