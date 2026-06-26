class Admin::GrokTasksController < Admin::BaseController
  def index
    @q = GrokTask.ransack(params[:q])
    @grok_tasks = @q.result.order(created_at: :desc).page(params[:page])
  end

  def show
    @grok_task = GrokTask.find(params[:id])
  end

  def new
    @grok_task = GrokTask.new
    @themes = Theme.pluck(:name)
    @images = GrokImageResource.all
    @accounts = Account.where(status: '正常', work_type: 'Grok')
    @platforms = GrokTask.platforms
  end

  def create
    @grok_task = GrokTask.new(grok_task_params)

    if @grok_task.save
      redirect_to admin_grok_tasks_path, notice: 'Grok 任务创建成功'
    else
      @themes = Theme.pluck(:name)
      @images = GrokImageResource.all
      @accounts = Account.where(status: '正常', work_type: 'Grok')
      @platforms = GrokTask.platforms
      render :new
    end
  end

  def edit
    @grok_task = GrokTask.find(params[:id])
    @themes = Theme.pluck(:name)
    @images = GrokImageResource.all
    @accounts = Account.where(status: '正常', work_type: 'Grok')
    @platforms = GrokTask.platforms
  end

  def update
    @grok_task = GrokTask.find(params[:id])

    if @grok_task.update(grok_task_params)
      redirect_to admin_grok_tasks_path, notice: 'Grok 任务更新成功'
    else
      @themes = Theme.pluck(:name)
      @images = GrokImageResource.all
      @accounts = Account.where(status: '正常', work_type: 'Grok')
      @platforms = GrokTask.platforms
      render :edit
    end
  end

  def destroy
    @grok_task = GrokTask.find(params[:id])
    @grok_task.destroy
    redirect_to admin_grok_tasks_path, notice: 'Grok 任务删除成功'
  end

  private

  def grok_task_params
    params.require(:grok_task).permit(
      :theme, :video_url, :status, :prompt, :grok_image_id, :account_id,
      :error_msg, :start_at, :actual_publish_time, :browser_id, :platform,
      :title, :description
    )
  end
end
