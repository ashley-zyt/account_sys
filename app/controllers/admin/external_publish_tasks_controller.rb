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
    @media_preview_urls = Array(@external_publish_task.media_urls).map { |u| XPublisher.resolve_media_url(u, @external_publish_task.media_type) }
  end

  def destroy
    task = ExternalPublishTask.find(params[:id])
    unless task.pending? || task.waiting_publish?
      redirect_to admin_external_publish_tasks_path, alert: "仅「待分配/待发布」状态的任务可删除"
      return
    end

    delete_task_media_files(task)
    task.destroy
    redirect_to admin_external_publish_tasks_path, notice: "任务删除成功"
  end

  private

  def delete_task_media_files(task)
    keys = Array(task.media_urls).map(&:to_s).reject(&:blank?).reject { |u| u.include?('://') }
    keys.each do |key|
      begin
        OssTransfer.hk_client.get_bucket('account-agic').delete_object(key)
      rescue => e
        msg = e.message.to_s
        next if msg.include?('404') || msg.include?('NoSuchKey') || msg.include?('NoSuchFile')
        Rails.logger.error "[ExternalPublishTasks] 删除 OSS 文件失败 key=#{key}: #{msg}"
      end
    end
  end

  def task_model_class
    ExternalPublishTask
  end
end
