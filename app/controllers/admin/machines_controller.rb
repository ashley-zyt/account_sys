class Admin::MachinesController < Admin::BaseController
  before_action :set_machine, only: [:edit, :update, :destroy]

  def index
    @machines = Machine.order(:id).includes(:browsers)
  end

  def new
    @machine = Machine.new
  end

  def create
    @machine = Machine.new(machine_params)
    if @machine.save
      redirect_to admin_machines_path, notice: '机器已创建'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @machine.update(machine_params)
      redirect_to admin_machines_path, notice: '机器已更新'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    # 机器被浏览器引用时，先解除关联再删除
    @machine.browsers.update_all(machine_id: nil)
    @machine.destroy
    redirect_to admin_machines_path, notice: '机器已删除'
  end

  private

  def set_machine
    @machine = Machine.find(params[:id])
  end

  def machine_params
    params.require(:machine).permit(:name, :host, :remark)
  end
end
