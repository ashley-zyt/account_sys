class Admin::BrowsersController < Admin::BaseController
	before_action :set_browser, only: [:show, :edit, :update]

	def index
		@q = Browser.ransack(params[:q])
		@browsers = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(10)
	end

	def new
		@browser = Browser.new
	end

	def create
		@browser = Browser.new(browser_params)
		if @browser.save
			redirect_to admin_browser_path(@browser), notice: "浏览器已成功创建"
		else
			render :new, status: :unprocessable_entity
		end
	end

	def show
		@accounts = @browser.accounts.order(created_at: :desc).limit(20)
		@move_tasks = @browser.move_tasks.order(created_at: :desc).limit(20)
	end

	def edit
	end

	def update
		if @browser.update(browser_params)
			redirect_to admin_browser_path(@browser), notice: "浏览器信息已更新"
		else
			render :edit, status: :unprocessable_entity
		end
	end

	private

	def set_browser
		@browser = Browser.find(params[:id])
	end

	def browser_params
		params.require(:browser).permit(
			:profile_name,
			:cloud_id,
			:proxy_type,
			:proxy_host,
			:proxy_port,
			:proxy_username,
			:proxy_password,
			:status,
			:purpose,
			:remark
		)
	end
end
