class Admin::HeygenTasksController < Admin::BaseController
  def index
    @q = HeygenTask.ransack(params[:q])
    @heygen_tasks = @q.result.order(created_at: :desc).page(params[:page])
  end

  def show
    @heygen_task = HeygenTask.find(params[:id])
  end

  def destroy
    @heygen_task = HeygenTask.find(params[:id])
    @heygen_task.destroy
    redirect_to admin_heygen_tasks_path, notice: 'Heygen 任务删除成功'
  end

  private

  def heygen_task_params
    params.require(:heygen_task).permit(
      :theme, :video_url, :status, :templete_id, :video_text, :account_id,
      :error_msg, :start_at, :actual_publish_time, :browser_id, :platform,
      :title, :description
    )
  end
end