class Admin::HostingPublishTasksController < Admin::BaseController
  def index
    @q = HostingPublishTask.ransack(params[:q])
    @hosting_publish_tasks = @q.result
                                .includes(:hosting_account, :client)
                                .order(created_at: :desc)
                                .page(params[:page])
  end
end
