class Admin::AccountsController < Admin::BaseController
	before_action :load_themes, only: [:new, :create]

	def index
		@q = Account.ransack(params[:q])
		@accounts = @q.result(distinct: true).order(created_at: :desc).page(params[:page]).per(10)
	end

	def new
		@account = Account.new
	end

	def create
		@account = Account.new(account_params)
		if @account.save
			redirect_to admin_account_path(@account)
		else
			render :new, status: :unprocessable_entity
		end
	end

	def show
		@account = Account.find(params[:id])
		@recent_tasks = @account.move_tasks.order(created_at: :desc).limit(10)
	end

	private

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
