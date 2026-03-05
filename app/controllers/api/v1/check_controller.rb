module Api
	module V1
		class CheckController < ApplicationController
			skip_before_action :verify_authenticity_token, only: [:account_status]
			def account_status
				datas = []
				Account.active.each do |account|
					browser = account.browser
					datas << {id:account.id,platform:account.platform,profile_name:browser.profile_name}
				end
				return render json: datas
			end
		end
	end
end