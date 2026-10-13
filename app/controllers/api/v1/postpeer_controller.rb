module Api
  module V1
    # postpeer 第三方发布平台回调接口。
    #
    # 授权是「机器端打开授权页 → 人工点击授权按钮」的异步流程。
    # 机器端在用户点击授权按钮后，主动回调本接口告知「该账号已点击完成授权」，
    # 本系统据此立即去 postpeer 查询 accountId（加速确认，不必等轮询器）。
    class PostpeerController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/postpeer/auth_callback
      # 入参：
      #   account_id      本系统账号 ID（必填）
      #   peer_account_id （可选）机器端若能直接拿到 postpeer 集成 ID（accountId）则带回；
      #                   否则本系统主动查 postpeer 反查。
      def auth_callback
        account_id = (params[:account_id] || params[:external_id]).to_s.strip
        account = account_id.present? ? Account.find_by(id: account_id) : nil
        return render json: { type: 'error', message: '账号不存在' }, status: 404 if account.nil?

        result = PostpeerAuthService.confirm_authorization(account, peer_account_id: params[:peer_account_id])
        if result
          render json: { type: 'success', message: '授权已确认', peer_account_id: result[:peer_account_id] }
        else
          render json: { type: 'success', message: '已收到授权点击通知，等待 postpeer 授权数据就绪' }
        end
      rescue => e
        Rails.logger.error "[Postpeer] 授权回调处理异常: #{e.message}"
        render json: { type: 'error', message: e.message }, status: 500
      end
    end
  end
end
