class Admin::GrokVideoResourcesController < Admin::BaseController
  def index
    @q = GrokVideoResource.ransack(params[:q])
    @grok_video_resources = @q.result.order(created_at: :desc).page(params[:page])
  end

  def new
    @grok_video_resource = GrokVideoResource.new
    @themes = Theme.pluck(:name)
    @images = GrokImageResource.all
    @accounts = Account.where(status: '正常')
    @platforms = GrokVideoResource.platforms
  end

  def create
    @grok_video_resource = GrokVideoResource.new(grok_video_resource_params)
    
    if @grok_video_resource.save
      redirect_to admin_grok_video_resources_path, notice: '视频储备创建成功'
    else
      @themes = Theme.pluck(:name)
      @images = GrokImageResource.all
      @accounts = Account.where(status: '正常')
      @platforms = GrokVideoResource.platforms
      render :new
    end
  end

  def edit
    @grok_video_resource = GrokVideoResource.find(params[:id])
    @themes = Theme.pluck(:name)
    @images = GrokImageResource.all
    @accounts = Account.where(status: '正常')
    @platforms = GrokVideoResource.platforms
  end

  def update
    @grok_video_resource = GrokVideoResource.find(params[:id])
    
    if @grok_video_resource.update(grok_video_resource_params)
      redirect_to admin_grok_video_resources_path, notice: '视频储备更新成功'
    else
      @themes = Theme.pluck(:name)
      @images = GrokImageResource.all
      @accounts = Account.where(status: '正常')
      @platforms = GrokVideoResource.platforms
      render :edit
    end
  end

  def destroy
    @grok_video_resource = GrokVideoResource.find(params[:id])
    @grok_video_resource.destroy
    redirect_to admin_grok_video_resources_path, notice: '视频储备删除成功'
  end

  private

  def grok_video_resource_params
    params.require(:grok_video_resource).permit(
      :theme, :video_url, :status, :prompt, :grok_image_id, :account_id,
      :error_msg, :start_at, :actual_publish_time, :browser_id, :platform,
      :title, :description
    )
  end
end