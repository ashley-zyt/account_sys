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

  def stats
    # 按运营机器 IP（记录在 warmup_tasks.machine）分组统计
    machine_ips = WarmupTask.where.not(machine: [nil, ""]).distinct.pluck(:machine).sort
    @machine_stats = machine_ips.map do |ip|
      task_counts = WarmupTask.where(machine: ip).group(:status).count
      browser_ids = Browser.where(machine_ip: ip).pluck(:id)
      total_accounts   = Account.where(browser_id: browser_ids, status: [0, 3]).count
      enabled_accounts = Account.joins(:warmup_profile)
                                .where(browser_id: browser_ids, status: [0, 3], warmup_profiles: { warmup_enabled: true })
                                .count
      {
        ip: ip,
        task_counts: task_counts,
        total_accounts: total_accounts,
        enabled_accounts: enabled_accounts,
        success: task_counts[2] || 0,   # status enum: success=2
        failed:  task_counts[3] || 0    # status enum: failed=3
      }
    end
    @total_success = @machine_stats.sum { |s| s[:success] }
    @total_failed  = @machine_stats.sum { |s| s[:failed] }
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