module Api
  module V1
    # X（Twitter）API 认证回调接口。
    #
    # 认证是「机器端打开授权页 → 用户授权 → 浏览器跳转 localhost?code=xxx → 机器端截 code」的异步流程。
    # 机器端截到授权码 code 后，主动 POST 本接口，本系统用 code + 暂存的 code_verifier 换 token。
    #
    # 机器端调用约定：
    #   下发认证时 ref = "XAuth:<account_id>"，机器端检测到浏览器跳转到 localhost 后从 URL 抠出 code，
    #   再取出 account_id，POST 本接口带回 code（state 可选）。
    class XAuthController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/x_auth/auth_callback
      # 入参：
      #   account_id  本系统账号 ID（必填）
      #   code        X 授权完成后回传的授权码（必填）
      #   state       （可选）防 CSRF，机器端若能从跳转 URL 抠到则带回
      def auth_callback
        account_id = params[:account_id].to_s.strip
        account = account_id.present? ? Account.find_by(id: account_id) : nil
        return render json: { type: 'error', message: '账号不存在' }, status: 404 if account.nil?

        code = params[:code].to_s.strip
        return render json: { type: 'error', message: '缺少授权码 code' }, status: 400 if code.blank?

        result = XAuthService.complete_authorization(account, code: code, state: params[:state])
        if result[:success]
          render json: { type: 'success', message: result[:message], x_user_id: result[:x_user_id] }
        else
          render json: { type: 'error', message: result[:message] }, status: 400
        end
      rescue => e
        Rails.logger.error "[XAuth] 认证回调处理异常: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        render json: { type: 'error', message: e.message }, status: 500
      end
    end
  end
end
