class Admin::HostingPublishTasksController < Admin::BaseController
  before_action :set_task, only: [:publish]

  def index
    @q = HostingPublishTask.ransack(params[:q])
    @hosting_publish_tasks = @q.result
                                .includes(:hosting_account, :client)
                                .order(created_at: :desc)
                                .page(params[:page])
  end

  # 手动执行发布：调用 postpeer 发布并回写结果
  def publish
    result = HostingPublishService.publish(@task)
    if result[:success]
      redirect_back fallback_location: admin_hosting_publish_tasks_path, notice: result[:message]
    else
      redirect_back fallback_location: admin_hosting_publish_tasks_path, alert: result[:message]
    end
  end

  private

  def set_task
    @task = HostingPublishTask.find(params[:id])
  end
end
