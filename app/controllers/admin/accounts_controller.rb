class Admin::AccountsController < Admin::BaseController
	before_action :set_account, only: [:show, :edit, :update]
	before_action :load_themes, only: [:index, :new, :create, :edit, :update]

	def index
		@q = Account.ransack(params[:q])
		@accounts = @q.result(distinct: true)
		             .left_joins(:browser)
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
		# 使用 task_logs.account_id 快照查询，能兼容运营任务被释放资源的场景
		@recent_task_logs = @account.task_logs
		                           .order(run_at: :desc)
		                           .limit(10)
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
