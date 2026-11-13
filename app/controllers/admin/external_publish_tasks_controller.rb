class Admin::ExternalPublishTasksController < Admin::BaseController
  include TaskExecutable

  def index
    @q = ExternalPublishTask.ransack(params[:q])
    @external_publish_tasks = @q.result(distinct: true)
                                .includes(:account, :browser, :external_resource)
                                .order(created_at: :desc)
                                .page(params[:page])
                                .per(20)
  end

  def show
    @external_publish_task = ExternalPublishTask.find(params[:id])
  end

  private

  def task_model_class
    ExternalPublishTask
  end
end
