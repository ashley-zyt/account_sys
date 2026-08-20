class Admin::MessageVariablesController < Admin::BaseController
  before_action :set_variable, only: [:edit, :update, :destroy]

  def index
    @q = MessageVariable.ransack(params[:q])
    @variables = @q.result(distinct: true)
                   .order(:id)
                   .page(params[:page])
                   .per(20)
  end

  def new
    @variable = MessageVariable.new
  end

  def create
    @variable = MessageVariable.new(variable_params)
    if @variable.save
      redirect_to admin_message_variables_path, notice: "变量已创建"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @variable.update(variable_params)
      redirect_to admin_message_variables_path, notice: "变量已更新"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @variable.destroy
    redirect_to admin_message_variables_path, notice: "变量已删除"
  end

  private

  def set_variable
    @variable = MessageVariable.find(params[:id])
  end

  def variable_params
    params.require(:message_variable).permit(:identifier, :name, :description)
  end
end
