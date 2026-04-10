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
			def update_account_status
				id = params[:id]
				account = Account.find_by(id:id)
				return render json: {type: 'error', message: "account不存在" } if account.nil?
				status_desp = params[:status_desp]
				status = "success"
				if !status_desp.nil? and status_desp != ""
					status = "failed"
					if status_desp.include?"page redirected" or status_desp.include?"page contains keyword"
						account.update(status:2)
					end
				end
				TaskLog.create(task_uuid:999,status:status,error_msg:status_desp,run_at:Time.now,response_data:params.to_s)
				return render json: {type: 'success', message: "状态已同步" }
			end
			# 获取需要续费的代理列表
			def valid_proxies
				browser_ids = Account.where(status:0).pluck("browser_id")
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
				return render json: ips
			end
		end
	end
end