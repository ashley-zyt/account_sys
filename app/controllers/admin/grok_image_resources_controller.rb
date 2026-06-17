class Admin::GrokImageResourcesController < Admin::BaseController
  def index
    @q = GrokImageResource.ransack(params[:q])
    @grok_image_resources = @q.result.order(created_at: :desc).page(params[:page])
  end

  def new
    @grok_image_resource = GrokImageResource.new
    @themes = Theme.pluck(:name)
  end

  def create
    @grok_image_resource = GrokImageResource.new(grok_image_resource_params)
    
    if @grok_image_resource.save
      redirect_to admin_grok_image_resources_path, notice: '图片储备创建成功'
    else
      @themes = Theme.pluck(:name)
      render :new
    end
  end

  def destroy
    @grok_image_resource = GrokImageResource.find(params[:id])
    @grok_image_resource.destroy
    redirect_to admin_grok_image_resources_path, notice: '图片储备删除成功'
  end

  private

  def grok_image_resource_params
    params.require(:grok_image_resource).permit(:theme, :image_url)
  end
end