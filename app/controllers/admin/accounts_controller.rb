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
			back_to_accounts_list("账号已成功创建")
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
			back_to_accounts_list("账号信息已更新")
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

	# 获取视频号登录二维码（代理转发到远端接口，带鉴权）
	# GET /admin/accounts/shipinhao_login_qrcode
	def shipinhao_login_qrcode
		url = "http://47.98.149.236:8080/accounts/shipinhao_login_qrcode?profile_name=domestic01"
		response = RemoteApiClient.get(url, open_timeout: 30, read_timeout: 60)
		body = response.body.to_s.dup.force_encoding('UTF-8')

		parsed = begin
			JSON.parse(body)
		rescue JSON::ParserError
			nil
		end

		if parsed
			render json: parsed
		else
			render json: { type: "error", error_info: "远端响应非JSON(HTTP #{response.code}): #{body.to_s.truncate(200)}" }
		end
	rescue => e
		render json: { type: "error", error_info: "请求异常: #{e.class} #{e.message}" }
	end

	private

	def back_to_accounts_list(notice)
		opts = {}
		opts[:q] = params[:q].to_unsafe_h if params[:q].present?
		opts[:page] = params[:page] if params[:page].present?
		redirect_to admin_accounts_path(opts), notice: notice
	end

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
