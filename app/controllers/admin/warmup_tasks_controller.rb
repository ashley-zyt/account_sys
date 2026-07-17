class Admin::WarmupTasksController < Admin::BaseController
  def index
    @q = WarmupTask.ransack(params[:q])
    @warmup_tasks = @q.result(distinct: true)
                       .includes(:account, :browser)
                       .order(created_at: :desc)
                       .page(params[:page])
                       .per(15)
  end

  def show
    @warmup_task = WarmupTask.find(params[:id])
  end

  def new
    @warmup_task = WarmupTask.new
    @accounts = Account.active.where("browser_id IS NOT NULL")
  end

  def create
    @warmup_task = WarmupTask.new(warmup_task_params)
    if @warmup_task.save
      redirect_to admin_warmup_tasks_path, notice: '养号任务创建成功'
    else
      @accounts = Account.active.where("browser_id IS NOT NULL")
      render :new
    end
  end

  def destroy
    @warmup_task = WarmupTask.find(params[:id])
    @warmup_task.destroy
    redirect_to admin_warmup_tasks_path, notice: '养号任务已删除'
  end

  def distribute_batches
    machine = params[:machine].to_sym
    total_batches = Account.distribute_warmup_batches(machine)
    redirect_to admin_warmup_tasks_path, notice: "已将账号分配到 #{total_batches} 个批次"
  end

  def stats
    @move_stats = WarmupTask.where(machine: 'move').group(:status).count
    @other_stats = WarmupTask.where(machine: 'other').group(:status).count
    @move_accounts = Account.active.where(work_type: '视频搬运').count
    @other_accounts = Account.active.where.not(work_type: '视频搬运').count
    @move_enabled_count = WarmupProfile.where(machine: 'move', warmup_enabled: true).count
    @other_enabled_count = WarmupProfile.where(machine: 'other', warmup_enabled: true).count
  end

  def execute
    @warmup_task = WarmupTask.find(params[:id])
    
    if @warmup_task.executing? || @warmup_task.success?
      redirect_to admin_warmup_task_path(@warmup_task), alert: '任务已在执行中或已完成'
      return
    end

    # 异步执行任务
    Thread.new do
      begin
        ExecuteWorker.execute_warmup_task(@warmup_task)
      rescue => e
        Rails.logger.error "[ExecuteWorker] 执行异常: #{e.message}"
        @warmup_task.update(status: :failed, error_msg: "执行异常: #{e.message}") rescue nil
      end
    end

    redirect_to admin_warmup_task_path(@warmup_task), notice: '任务已开始执行'
  end

  private

  def warmup_task_params
    params.require(:warmup_task).permit(:account_id, :platform)
  end
end