module Api
  module V1
    # postforme 第三方发布平台回调接口。
    #
    # 授权是「机器端打开授权页 → 人工点击授权按钮」的异步流程。
    # 机器端在用户点击授权按钮后，主动回调本接口告知「该账号已点击完成授权」，
    # 本系统据此立即去 postforme 查询 social_account_id（加速确认，不必等 1 分钟轮询器）。
    #
    # 机器端调用约定：
    #   下发授权时 ref = "PostformeAuth:<account_id>"，机器端点击授权按钮后从 ref 里取出
    #   account_id，POST 本接口并带回。若机器端能直接拿到 postforme 社交账号 ID，也可一并带回。
    class PostformeController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/postforme/auth_callback
      # 入参：
      #   account_id        本系统账号 ID（必填；也兼容 postforme 概念里的 external_id 字段名）
      #   social_account_id （可选）机器端若能直接拿到 postforme 社交账号 ID（spc_xxx）则带回；
      #                     否则本系统主动查 postforme 反查。
      # 返回：{ type: "success" }。无论是否已确认，只要收到通知就回 success，
      #       避免机器端误判为失败而反复重试。
      def auth_callback
        account_id = (params[:account_id] || params[:external_id]).to_s.strip
        account = account_id.present? ? Account.find_by(id: account_id) : nil
        return render json: { type: 'error', message: '账号不存在' }, status: 404 if account.nil?

        result = PostformeAuthService.confirm_authorization(account, social_account_id: params[:social_account_id])
        if result
          render json: { type: 'success', message: '授权已确认', social_account_id: result[:social_account_id] }
        else
          render json: { type: 'success', message: '已收到授权点击通知，等待 postforme 授权数据就绪' }
        end
      rescue => e
        Rails.logger.error "[Postforme] 授权回调处理异常: #{e.message}"
        render json: { type: 'error', message: e.message }, status: 500
      end
    end
  end
end
