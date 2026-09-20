class Admin::BrowserTaskRecordsController < Admin::BaseController
  # 异步任务登记列表（下发到机器端的 async 任务），用于查看执行状态
  def index
    @q = BrowserTaskRecord.ransack(params[:q])
    @records = @q.result(distinct: true)
                 .order(created_at: :desc)
                 .page(params[:page])
                 .per(20)
  end

  # 手动触发一次超时兜底同步（查机器端真实状态补结果或重置）
  def sync
    TaskScheduler.check_timeout_tasks
    redirect_back fallback_location: admin_browser_task_records_path, notice: "已同步异步任务状态"
  end
end
