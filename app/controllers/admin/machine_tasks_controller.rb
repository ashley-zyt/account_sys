class Admin::MachineTasksController < Admin::BaseController
  # 运营机器任务监控：实时聚合查询各机器上各类任务的进度与堆积
  #
  # 不落库、不缓存：机器端任务态在内存里，天生实时；每次进来查一次（多机并行，单机 5~15s 超时）。
  def index
    @results    = MachineTaskMonitor.fetch_all
    @fetched_at = Time.current
    @auto       = params[:auto].present?   # ?auto=1 开启 30 秒自动刷新
  end

  # 可选：JSON 版本，方便接外部监控 / 钉钉告警
  def summary
    results = MachineTaskMonitor.fetch_all

    render json: {
      fetched_at: Time.current.strftime('%Y-%m-%d %H:%M:%S'),
      machines: results.map do |r|
        {
          machine_ip:  r.machine_ip,
          ok:          r.ok,
          error:       r.error,
          status_counts: r.ok ? r.data['status_counts'] : nil,
          type_status_counts: r.ok ? r.data['type_status_counts'] : nil,
          backlog:     r.ok ? (r.data['profiles'] || []).first(20) : nil,
          oldest_queued_seconds: r.ok ? r.data['oldest_queued_seconds'] : nil
        }
      end
    }
  end
end
