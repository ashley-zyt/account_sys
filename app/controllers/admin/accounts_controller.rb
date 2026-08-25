class Admin::AccountsController < Admin::BaseController
	before_action :set_account, only: [:show, :edit, :update, :toggle_warmup, :destroy]
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
		# 最近十条养号记录
		@recent_warmup_tasks = @account.warmup_tasks
		                               .order(executed_at: :desc)
		                               .limit(10)
		# 采集到的最近十条发文数据
		@recent_post_stats = @account.post_stats
		                             .order(post_date: :desc)
		                             .limit(10)
		# 粉丝量/发帖量历史数据（近30天，用于趋势图）
		@follower_history = @account.account_stats
		                            .where("stat_date >= ?", 30.days.ago.to_date)
		                            .order(stat_date: :asc)
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

	def toggle_warmup
		profile = @account.warmup_profile || @account.create_warmup_profile
		profile.update!(warmup_enabled: !profile.warmup_enabled)
		redirect_back fallback_location: admin_account_path(@account), notice: "养号开关已#{profile.warmup_enabled ? '启用' : '停止'}"
	end

	# 软删除：写入 deleted_at 时间戳，不物理删除记录
	def destroy
		@account.soft_delete!
		redirect_to admin_accounts_path, notice: "账号「#{@account.account_name}」已删除"
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
