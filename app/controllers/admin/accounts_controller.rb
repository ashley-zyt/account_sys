class Admin::AccountsController < Admin::BaseController
	before_action :set_account, only: [:show, :edit, :update, :toggle_warmup, :refresh_stats, :start_postforme_auth, :start_x_auth, :start_manual_x_auth, :complete_manual_x_auth, :destroy]
	before_action :load_themes, only: [:index, :new, :create, :edit, :update]

	def index
		@q = Account.ransack(params[:q])
		@accounts = @q.result(distinct: true)
		             .left_joins(:browser)
		             .includes(:browser)
		             .order(created_at: :desc)
		             .page(params[:page])
		             .per(10)

		# 预计算 KOL 触达近 3 天成功率：[成功数, 已完成发送数(成功+失败)]
		@kol_outreach_stats = {}
		ids = @accounts.map(&:id)
		if ids.any?
			counts = KolMessage.where(account_id: ids, direction: :outgoing,
			                          status: [:sent_success, :sent_failed])
			                   .where(created_at: 3.days.ago..Time.current)
			                   .group(:account_id, :status).count
			ids.each do |id|
				success = counts[[id, KolMessage.statuses[:sent_success]]].to_i
				failed  = counts[[id, KolMessage.statuses[:sent_failed]]].to_i
				@kol_outreach_stats[id] = [success, success + failed]
			end
		end
	end

	# 一键导出：按当前搜索条件导出全部账号（所有字段 + 页面上的最后使用时间/最后运行错误）
	def export
		require 'csv'
		@q = Account.ransack(params[:q])
		accounts = @q.result(distinct: true)
		             .left_joins(:browser)
		             .includes(:browser)
		             .order(created_at: :desc)

		filename = "账号列表_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"
		response.headers['Content-Type'] = 'text/csv; charset=utf-8'
		response.headers['Content-Disposition'] = "attachment; filename=#{filename}"

		csv_data = CSV.generate(encoding: 'utf-8') do |csv|
			csv << ['ID', '账号名', '账号链接', '主题', '平台', '状态', '工作模式', '运营人员',
			        '浏览器ID', '绑定浏览器', '最后使用时间', '最后运行错误', '备注',
			        'KOL休眠截止', '创建时间', '更新时间', '删除时间']

			accounts.find_each do |a|
				last_log = a.last_task_log
				last_error = if last_log && last_log.status == 'failed'
					last_log.error_msg
				elsif last_log && last_log.status == 'success'
					'正常（最后运行成功）'
				else
					''
				end

				csv << [
					a.id,
					a.account_name,
					a.source_url,
					a.theme,
					a.platform,
					a.status,
					a.work_type,
					a.operator.presence || '-',
					a.browser_id,
					a.browser&.profile_name || '-',
					a.last_used_at&.strftime('%Y-%m-%d %H:%M') || '-',
					last_error.to_s,
					a.remark,
					a.kol_sleep_until&.strftime('%Y-%m-%d %H:%M') || '-',
					a.created_at&.strftime('%Y-%m-%d %H:%M'),
					a.updated_at&.strftime('%Y-%m-%d %H:%M'),
					a.deleted_at&.strftime('%Y-%m-%d %H:%M') || '-'
				]
			end
		end

		csv_data = "\xEF\xBB\xBF" + csv_data
		render plain: csv_data
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

	# 立即采集单个账号的粉丝/发文数据（异步推送采集指令到运营机器，落库由采集端回传完成）
	def refresh_stats
		account_id = @account.id
		Thread.new do
			ActiveRecord::Base.connection_pool.with_connection do
				begin
					Util.fetch_account_post_data(account_id: account_id)
				rescue => e
					Rails.logger.error "[AccountsController] 账号 ##{account_id} 立即更新失败: #{e.message}"
				end
			end
		end
		redirect_back fallback_location: admin_account_path(@account), notice: "已触发采集，粉丝与发文数据稍后更新（通常 1~2 分钟）"
	end

	# 发起 postforme 授权：拿授权 URL → 记录「授权中」→ 下发机器端打开授权页
	def start_postforme_auth
		result = PostformeAuthService.start_authorization(@account)
		if result[:success]
			redirect_back fallback_location: admin_account_path(@account), notice: result[:message]
		else
			redirect_back fallback_location: admin_account_path(@account), alert: result[:message]
		end
	end

	# 发起 X（Twitter）API 认证：生成 PKCE → 记录「认证中」→ 下发机器端打开授权页
	def start_x_auth
		# 由 XAuthService 自动判断：正常「认证中」不覆盖（防止旧授权页 code 撞新 state），
		# 卡死（超过阈值）才覆盖，兼顾「卡死能重发」与「不误覆盖进行中的认证」。
		result = XAuthService.start_authorization(@account)
		if result[:success]
			redirect_back fallback_location: admin_account_path(@account), notice: result[:message]
		else
			redirect_back fallback_location: admin_account_path(@account), alert: result[:message]
		end
	end

	# 全手动发起 X 认证：只生成授权链接（不下发机器端），链接存 flash 展示给用户复制
	def start_manual_x_auth
		result = XAuthService.start_authorization(@account, skip_machine: true)
		if result[:success]
			flash[:manual_auth_url] = result[:auth_url]
			redirect_back fallback_location: admin_account_path(@account), notice: result[:message]
		else
			redirect_back fallback_location: admin_account_path(@account), alert: result[:message]
		end
	end

	# 全手动完成 X 认证：用户粘贴授权码（或整段回调 URL），解析后换 token
	def complete_manual_x_auth
		raw = params[:code].to_s.strip
		if raw.blank?
			return redirect_back fallback_location: admin_account_path(@account), alert: '请粘贴授权码或回调 URL'
		end

		code, state = parse_manual_auth_input(raw)
		if code.blank?
			return redirect_back fallback_location: admin_account_path(@account), alert: '无法从粘贴内容中解析出授权码'
		end

		result = XAuthService.complete_authorization(@account, code: code, state: state)
		if result[:success]
			redirect_back fallback_location: admin_account_path(@account), notice: result[:message]
		else
			redirect_back fallback_location: admin_account_path(@account), alert: result[:message]
		end
	end

	# 软删除：写入 deleted_at 时间戳，不物理删除记录
	def destroy
		@account.soft_delete!
		redirect_to admin_accounts_path, notice: "账号「#{@account.account_name}」已删除"
	end

	# 视频号登录二维码页面（仅渲染页面，不自动请求，点击按钮后由前端 fetch 触发）
	# GET /admin/accounts/shipinhao_login_qrcode?profile_name=domestic01
	def shipinhao_login_qrcode
		@profile_name = valid_profile_name(params[:profile_name])
	end

	# 获取视频号登录二维码数据（代理转发到远端接口，带鉴权），返回 JSON
	# GET /admin/accounts/shipinhao_login_qrcode_data?profile_name=domestic01
	def shipinhao_login_qrcode_data
		profile_name = valid_profile_name(params[:profile_name])
		url = "http://47.98.149.236:8080/accounts/shipinhao_login_qrcode?profile_name=#{profile_name}"
		response = RemoteApiClient.get(url, open_timeout: 30, read_timeout: 60)
		body = response.body.to_s.dup.force_encoding('UTF-8')

		data = begin
			JSON.parse(body)
		rescue JSON::ParserError
			nil
		end

		return render json: { type: "error", error_info: "远端响应非JSON(HTTP #{response.code})" } if data.nil?

		login_status = data.dig("login_status").to_s
		profile_id   = data.dig("profile_id").to_s
		qrcode       = data.dig("qrcode_image").to_s

		# 已登录，无需扫码（无 qrcode_image 字段）
		return render json: { type: "success", login_status: login_status, profile_id: profile_id } if login_status == "already_logged_in"

		return render json: { type: "error", error_info: "二维码数据为空" } if qrcode.blank?

		unless qrcode.match?(/\A[A-Za-z0-9+\/=]+\z/)
			return render json: { type: "error", error_info: "二维码数据格式异常：远端应返回 base64 编码" }
		end

		render json: {
			type: "success",
			login_status: login_status,
			profile_id: profile_id,
			qrcode_data_uri: "data:image/png;base64,#{qrcode}"
		}
	rescue => e
		render json: { type: "error", error_info: "请求异常: #{e.class} #{e.message}" }
	end

	private

	def valid_profile_name(value)
		name = value.presence || "domestic01"
		%w[domestic01 domestic02].include?(name) ? name : "domestic01"
	end

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
			:publish_channel,
			:browser_id,
			:operator,
			:remark
		)
	end

	# 解析用户粘贴的内容：支持「整段回调 URL（含 ?code=...&state=...）」或「纯 code」。
	# @return [Array] [code, state]
	def parse_manual_auth_input(raw)
		return [nil, nil] if raw.blank?

		# 整段 URL：解析 query 参数里的 code/state
		if raw.include?('code=')
			require 'uri'
			uri = URI.parse(raw)
			params = URI.decode_www_form(uri.query.to_s).to_h
			return [params['code'].to_s.presence, params['state'].to_s.presence]
		end

		[raw, nil]
	rescue
		[raw, nil]
	end
end
