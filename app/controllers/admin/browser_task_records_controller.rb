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

  # 主动重跑「被中断」的发布任务
  #
  # 场景：机器端进程重启/崩溃后，之前下发但没回调的发布任务会被兜底重置回 pending，
  # 但要等该平台下一个固定分配窗口（如 IG 早上崩掉、得等到第二天 7:50）才会重跑。
  # 这个入口点了就立刻重新分配 + 下发，不等窗口。
  #
  # 实现：先同步数一下有几条（快，用于给出明确提示），再把「分配 + 发布」放到后台线程执行
  #      —— 整个流程要逐台机器下发、耗时数分钟，同步跑会让页面卡住甚至超时。
  def retry_interrupted
    interrupted = TaskScheduler.interrupted_pending_tasks

    if interrupted.empty?
      redirect_back(fallback_location: admin_browser_task_records_path,
                    alert: "没有发现被中断的发布任务（未被兜底重置过）")
      return
    end

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          TaskScheduler.retry_interrupted_tasks
        rescue => e
          Rails.logger.error "[BrowserTaskRecords] 重跑被中断任务异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        end
      end
    end

    summary = interrupted.group_by(&:platform).map { |pf, ts| "#{pf} #{ts.size} 条" }.join("、")
    redirect_back(fallback_location: admin_browser_task_records_path,
                  notice: "已开始重跑 #{interrupted.size} 条被中断的发布任务（#{summary}），后台执行中，请稍后刷新查看")
  end
end
