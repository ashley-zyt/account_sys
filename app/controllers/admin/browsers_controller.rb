class Admin::BrowsersController < Admin::BaseController
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
			redirect_to admin_browser_path(@browser)
		else
			render :new, status: :unprocessable_entity
		end
	end

	def show
		@browser = Browser.find(params[:id])
		@accounts = @browser.accounts.order(created_at: :desc).limit(20)
		@move_tasks = @browser.move_tasks.order(created_at: :desc).limit(20)
	end

	private

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
