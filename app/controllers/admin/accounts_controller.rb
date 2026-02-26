class Admin::AccountsController < Admin::BaseController
	before_action :set_account, only: [:show, :edit, :update]
	before_action :load_themes, only: [:new, :create, :edit, :update]

	def index
		@q = Account.ransack(params[:q])
		@accounts = @q.result(distinct: true)
		             .includes(:browser)
		             .order(created_at: :desc)
		             .page(params[:page])
		             .per(10)
	end

	def new
		@account = Account.new
	end

	def create
		@account = Account.new(account_params)
		if @account.save
			redirect_to admin_account_path(@account), notice: "账号已成功创建"
		else
			render :new, status: :unprocessable_entity
		end
	end

	def show
		@recent_tasks = @account.move_tasks.order(created_at: :desc).limit(10)
	end

	def edit
	end

	def update
		if @account.update(account_params)
			redirect_to admin_account_path(@account), notice: "账号信息已更新"
		else
			render :edit, status: :unprocessable_entity
		end
	end

	private

	def set_account
		@account = Account.find(params[:id])
	end

	def load_themes
		raw = ThemeConfig.config["themes"]
		@themes =
			if raw.is_a?(Hash)
				raw.keys
			elsif raw.is_a?(Array)
				raw.map { |t| t["name"] }.compact
			else
				[]
			end
	end

	def account_params
		params.require(:account).permit(
			:account_name,
			:theme,
			:platform,
			:status,
			:work_type,
			:browser_id,
			:remark
		)
	end
end
