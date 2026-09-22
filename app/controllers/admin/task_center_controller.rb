class Admin::TaskCenterController < Admin::BaseController
  # 任务中心 —— 统一管理/查看页面
  #
  # 把原先分散的两个页面合并到一个入口：
  #   - 上半部分：机器端实时进度/堆积（MachineTaskMonitor 实时查询，不落库）
  #   - 下半部分：本地登记明细（BrowserTaskRecord，分页 + 筛选）
  # 并集中三个管理操作：同步状态 / 重跑丢失任务 / 清除任务。
  def index
    # 机器端实时数据（多机并行查询）。
    # own_only: false —— 不过滤 ref 前缀，把「人工/外部直接调 API 的任务」也一并展示，
    # 让任务中心能看到机器端全部任务（含 account_sys 下发 + 人工调用）。
    @results    = MachineTaskMonitor.fetch_all(own_only: false)
    @fetched_at = Time.current
    @auto       = params[:auto].present?

    # 本地登记明细（分页 + 筛选）
    @q = BrowserTaskRecord.ransack(params[:q])
    @records = @q.result(distinct: true)
                 .order(created_at: :desc)
                 .page(params[:page])
                 .per(20)

    # 清除任务的候选值
    @machines   = MachineTaskMonitor.machine_ips
    @task_types = MachineTaskMonitor::TYPE_LABELS
    @statuses   = MachineTaskMonitor::STATUSES
  end

  # JSON 版本（保留自原「机器任务监控」页，供外部监控 / 钉钉告警调用）
  def summary
    results = MachineTaskMonitor.fetch_all(own_only: false)

    render json: {
      fetched_at: Time.current.strftime('%Y-%m-%d %H:%M:%S'),
      machines: results.map do |r|
        {
          machine_ip:  r.machine_ip,
          ok:          r.ok,
          error:       r.error,
          status_counts:      r.ok ? r.data['status_counts'] : nil,
          type_status_counts: r.ok ? r.data['type_status_counts'] : nil,
          backlog:            r.ok ? (r.data['profiles'] || []).first(20) : nil,
          oldest_queued_seconds: r.ok ? r.data['oldest_queued_seconds'] : nil
        }
      end
    }
  end

  # 手动触发一次超时兜底同步（查机器端真实状态补结果或重置）
  def sync
    TaskScheduler.check_timeout_tasks
    redirect_back fallback_location: admin_task_center_index_path, notice: "已同步异步任务状态"
  end

  # 主动重跑「被中断」的发布任务（不等平台固定窗口）
  def retry_interrupted
    interrupted = TaskScheduler.interrupted_pending_tasks

    if interrupted.empty?
      redirect_back(fallback_location: admin_task_center_index_path,
                    alert: "没有发现被中断的发布任务（未被兜底重置过）")
      return
    end

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          TaskScheduler.retry_interrupted_tasks
        rescue => e
          Rails.logger.error "[TaskCenter] 重跑被中断任务异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        end
      end
    end

    summary = interrupted.group_by(&:platform).map { |pf, ts| "#{pf} #{ts.size} 条" }.join("、")
    redirect_back(fallback_location: admin_task_center_index_path,
                  notice: "已开始重跑 #{interrupted.size} 条被中断的发布任务（#{summary}），后台执行中，请稍后刷新查看")
  end

  # 批量重新启动失败的任务（本地登记明细勾选失败记录后触发）
  def retry_failed
    ids = Array(params[:record_ids]).map(&:to_i).reject(&:zero?)
    if ids.empty?
      redirect_back fallback_location: admin_task_center_index_path, alert: "请先勾选要重新启动的任务"
      return
    end

    # 发文/养号/采集下发都要走 HTTP，可能较慢，放到后台线程执行，接口立即返回
    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        begin
          result = TaskScheduler.retry_failed_records(ids)
          Rails.logger.info "[TaskCenter] 重新启动失败任务完成: #{result.inspect}"
        rescue => e
          Rails.logger.error "[TaskCenter] 重新启动失败任务异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        end
      end
    end

    redirect_back fallback_location: admin_task_center_index_path,
                  notice: "已开始重新启动 #{ids.size} 条失败任务，后台执行中，请稍后刷新查看"
  end

  # 清除任务：调指定机器的 POST /tasks/clear（可指定类型/状态）
  #
  # 安全约束：必须选机器；类型/状态至少指定一项（避免误触全量清空）。
  def clear
    machine_ip = params[:machine_ip].to_s.strip
    types      = Array(params[:type]).map(&:to_s).reject(&:blank?)
    statuses   = Array(params[:status]).map(&:to_s).reject(&:blank?)

    if machine_ip.empty?
      redirect_back fallback_location: admin_task_center_index_path, alert: "请选择要清除的机器"
      return
    end
    if types.empty? && statuses.empty?
      redirect_back fallback_location: admin_task_center_index_path, alert: "请至少指定任务类型或状态（避免全量清空）"
      return
    end

    query = {}
    query[:type]   = types.join(',')    if types.any?
    query[:status] = statuses.join(',') if statuses.any?
    url = "https://#{machine_ip}/tasks/clear?#{query.to_query}"

    begin
      resp = RemoteApiClient.post(url, {}, read_timeout: 30)
      if resp.code.to_i == 200
        count = (JSON.parse(resp.body) rescue {})['count']
        redirect_back fallback_location: admin_task_center_index_path, notice: "已清除 #{machine_ip} 上 #{count || 'N'} 个任务"
      else
        redirect_back fallback_location: admin_task_center_index_path,
                      alert: "清除失败：#{remote_error_message(resp)}"
      end
    rescue => e
      redirect_back fallback_location: admin_task_center_index_path, alert: "清除异常：#{e.message}"
    end
  end

  # 机器端任务明细列表（GET /tasks）—— 从各机器卡片「查看任务明细」进入
  #
  # 支持机器端全部过滤参数：type / status / profile_name / batch / ref_prefix（后三个单值，前两个逗号分隔多值）+ limit。
  def machines
    @machines   = MachineTaskMonitor.machine_ips
    @machine_ip = params[:machine_ip].to_s.strip
    @machine_ip = @machines.first if @machine_ip.empty?

    @task_types = MachineTaskMonitor::TYPE_LABELS

    @filters = {
      type:         params[:type],
      status:       params[:status],
      profile_name: params[:profile_name].to_s.strip,
      batch:        params[:batch].to_s.strip,
      ref_prefix:   params[:ref_prefix].to_s.strip
    }
    # 默认「全部任务」，与总览页各机器卡片的统计口径保持一致
    @own_only = params[:own_only].to_s == '1'
    @limit    = MachineTaskMonitor.normalize_limit(
      params[:limit].presence || MachineTaskMonitor::LIST_DEFAULT_LIMIT
    )

    @result = if @machine_ip.present?
                MachineTaskMonitor.fetch_tasks(
                  @machine_ip,
                  types:        @filters[:type],
                  statuses:     @filters[:status],
                  profile_name: @filters[:profile_name],
                  batch:        @filters[:batch],
                  ref_prefix:   @filters[:ref_prefix],
                  limit:        @limit,
                  own_only:     @own_only
                )
              end
    @tasks      = @result&.ok ? MachineTaskMonitor.normalize_tasks(@result.data) : []
    @fetched_at = Time.current
    @back_params = task_filter_params
  end

  # 机器端单个任务详情（GET /tasks/{id}）
  def machine_task
    @machine_ip = params[:machine_ip].to_s.strip
    @task_id    = params[:task_id].to_s.strip
    @result     = MachineTaskMonitor.fetch_task(@machine_ip, @task_id)

    # 返回列表时保留筛选条件
    @back_params = task_filter_params
  end

  # 人工确认启动：调指定机器的 POST /tasks/resume，
  # 让机器端重新探测 Undetectable，成功后恢复所有「因未启动而暂停」的发布任务。
  def resume
    machine_ip = params[:machine_ip].to_s.strip
    if machine_ip.empty?
      redirect_back fallback_location: admin_task_center_index_path, alert: "请选择要确认启动的机器"
      return
    end

    url = "https://#{machine_ip}/tasks/resume"
    begin
      # 机器端 resume 会探测 Undetectable（必要时拉起，最多约 20 秒），超时放宽到 70 秒。
      resp = RemoteApiClient.post(url, {}, read_timeout: 70)
      if resp.code.to_i == 200
        count = (JSON.parse(resp.body) rescue {})['count']
        redirect_back fallback_location: admin_task_center_index_path,
                      notice: "已确认启动 #{machine_ip}，恢复 #{count || 0} 个暂停的发布任务"
      else
        redirect_back fallback_location: admin_task_center_index_path,
                      alert: "确认启动失败：#{remote_error_message(resp)}"
      end
    rescue => e
      redirect_back fallback_location: admin_task_center_index_path, alert: "确认启动异常：#{e.message}"
    end
  end

  private

  # 机器端错误响应统一格式 {"type":"error","error_info":"..."}，优先取可读原因
  # （如 resume 的 503「Undetectable 仍不可用…」、详情页的 404「task not found」）
  def remote_error_message(resp)
    info = (JSON.parse(resp.body.to_s)['error_info'] rescue nil)
    info.present? ? info : "HTTP #{resp.code} #{resp.body.to_s[0, 200]}"
  end

  # 机器端明细列表的筛选条件（type/status 归一成数组），用于「刷新 / 返回列表」保留条件
  def task_filter_params
    permitted = params.permit(:machine_ip, :profile_name, :batch, :ref_prefix,
                              :limit, :own_only).to_h
    %w[type status].each do |key|
      values = MachineTaskMonitor.split_multi(params[key])
      permitted[key] = values if values.any?
    end
    permitted
  end
end
