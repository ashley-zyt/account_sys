class Admin::AccountsController < Admin::BaseController
	before_action :set_account, only: [:show, :edit, :update]
	before_action :load_themes, only: [:index, :new, :create, :edit, :update]

	def index
		@q = Account.ransack(params[:q])
		@accounts = @q.result(distinct: true)
		             .left_joins(:browser)
		             .includes(:browser)
		             .order(created_at: :desc)

		# 账号名搜索同时支持按浏览器名匹配
		if (keyword = params.dig(:q, :account_name_cont)).present?
			pattern = "%#{ActiveRecord::Base.sanitize_sql_like(keyword)}%"
			@accounts = @accounts.where(
				"accounts.account_name LIKE :pattern OR browsers.profile_name LIKE :pattern",
				pattern: pattern
			)
		end

		@accounts = @accounts.page(params[:page]).per(10)
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
		@themes = Theme.all_names
	end

	def account_params
		params.require(:account).permit(
			:account_name,
			:source_url,
			:theme,
			:platform,
			:status,
			:work_type,
			:browser_id,
			:operator,
			:remark
		)
	end
end
