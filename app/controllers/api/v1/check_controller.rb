module Api
	module V1
		class CheckController < ApplicationController
			skip_before_action :verify_authenticity_token, only: [:account_status,:update_account_status]
			def account_status
				datas = []
				Account.active.each do |account|
					browser = account.browser
					datas << {id:account.id,platform:account.platform,profile_name:browser.profile_name}
				end
				return render json: datas
			end
			def update_account_status
				id = params[:id]
				account = Account.find_by(id:id)
				return render json: {type: 'error', message: "account不存在" } if account.nil?
				status_desp = params[:status_desp]
				if !status_desp.nil? or status_desp != ""
					account.update(status:2,status_desp:status_desp)
				end
				return render json: {type: 'success', message: "状态已同步" }
			end
		end
	end
end