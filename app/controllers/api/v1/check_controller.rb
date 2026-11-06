module Api
	module V1
		class CheckController < ApplicationController
			skip_before_action :verify_authenticity_token, only: [:accounts,:update_account_status]
			def accounts
				datas = []
				Account.active.each do |account|
					browser = account.browser
					datas << {id:account.id,platform:account.platform,profile_name:browser.profile_name}
				end
				# account = Account.find(4)
				# browser = account.browser
				# datas << {id:account.id,platform:account.platform,profile_name:browser.profile_name}
				return render json: datas
			end
			# 机器端单独上报账号异常（巡检/发文时页面级异常）。
			# 复用 TaskReportHelper 统一封禁体系：关键词分类（封禁/未登录/网络等，
			# 含 ERR_TOO_MANY_REDIRECTS、performing security verification）→
			# 状态变更 + AccountChangeLog 变更记录 + 浏览器无效 + 养号联动。
			# 入参保持兼容：id + status_desp，机器端无需改动。
			def update_account_status
				id = params[:id]
				account = Account.find_by(id:id)
				return render json: {type: 'error', message: "account不存在" } if account.nil?
				status_desp = params[:status_desp].presence
				status = "success"
				if status_desp
					status = "failed"
					TaskReportHelper.check_account_abnormal(account.id, status_desp, source_action: '机器端状态上报')
				end
				TaskLog.create(
					task_uuid: "account_status_report",
					account_id: account.id,
					status: status,
					error_msg: TaskReportHelper.safe_utf8(status_desp),
					run_at: Time.now,
					response_data: TaskReportHelper.safe_utf8(params.to_s)
				)
				return render json: {type: 'success', message: "状态已同步" }
			end
			# 获取需要续费的代理列表
			def valid_proxies
				browser_ids = Account.where(status:[0,3]).pluck("browser_id")
				hosts = Browser.where(id:browser_ids).pluck("proxy_host")
				ips = []
				hosts.each do |host|
					if host.include?":"
						ip = host.split(":").first rescue ""
						if ip.nil? or ip != ""
							ips << ip
						end
					else
						ips << host
					end
				end
				return render json: ips.uniq
			end
		end
	end
end