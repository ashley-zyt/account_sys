module Api
  module V1
    # X 账号 access_token 下发接口：供外部机器定时获取最新 token。
    #
    # 鉴权：复用 auth/login（Bearer token，24h 有效），见 BaseController#authenticate_token!
    # 接口：
    #   GET /api/v1/x_tokens/latest?account_id=123   返回单个账号的最新 token
    #   GET /api/v1/x_tokens/latest                  返回所有已授权账号的 token 列表
    #
    # 说明：
    #   - access_token 约 2 小时过期，走 XAuthService.access_token_for 获取，
    #     过期会自动用 refresh_token 刷新并回写数据库，外部拿到的永远是当前有效的。
    #   - refresh_token 不下发（X 是轮换机制，必须由系统统一刷新回写）。
    class XTokensController < BaseController
      def latest
        if params[:account_id].present? || params[:account_name].present?
          render_single
        else
          render_list
        end
      end

      private

      def render_single
        account = find_account
        return if performed?

        xc = account.x_credential
        return render_error(msg: "账号 #{account.id} 未授权 X（auth_status=#{xc&.auth_status}）") unless xc&.authorized?

        token = XAuthService.access_token_for(account)
        return render_error(msg: "获取 token 失败（刷新失败，可能需重新认证）") if token.blank?

        render_success(data: token_data(account, xc, token))
      end

      def render_list
        items = []
        XCredential.where(auth_status: :authorized).includes(:account).find_each do |xc|
          account = xc.account
          next unless account
          token = XAuthService.access_token_for(account)
          next if token.blank?
          items << token_data(account, xc, token)
        end
        render_success(data: items)
      end

      def find_account
        account = if params[:account_id].present?
                    Account.find_by(id: params[:account_id])
                  else
                    Account.find_by(account_name: params[:account_name].to_s.strip)
                  end
        render_error(msg: "账号不存在") unless account
        account
      end

      def token_data(account, xc, token)
        {
          account_id: account.id,
          account_name: account.account_name,
          x_user_id: xc.reload.x_user_id,
          access_token: token,
          token_expires_at: xc.token_expires_at
        }
      end
    end
  end
end
