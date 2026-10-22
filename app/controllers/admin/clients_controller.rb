class Admin::ClientsController < Admin::BaseController
  before_action :set_client, only: [:update, :destroy]

  def index
    @q = Client.ransack(params[:q])
    @clients = @q.result.order(created_at: :desc).page(params[:page])
  end

  def create
    @client = Client.new(client_params)
    respond_to do |format|
      if @client.save
        format.html { redirect_to admin_clients_path, notice: '客户已添加' }
        format.json { render json: { success: true, message: '客户已添加' } }
      else
        format.html { render :new_modal, layout: false, status: :unprocessable_entity }
        format.json { render json: { success: false, message: @client.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  def update
    respond_to do |format|
      if @client.update(client_params)
        format.html { redirect_to admin_clients_path, notice: '客户已更新' }
        format.json { render json: { success: true, message: '客户已更新' } }
      else
        format.html { render :edit_modal, layout: false, status: :unprocessable_entity }
        format.json { render json: { success: false, message: @client.errors.full_messages.join(', ') }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @client.destroy
    redirect_to admin_clients_path, notice: '客户已删除'
  end

  def new_modal
    @client = Client.new
    render layout: false
  end

  def edit_modal
    @client = Client.find(params[:id])
    render layout: false
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(:name, :contact, :contact_info, :status, :remark)
  end
end
