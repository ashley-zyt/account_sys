module Api
  module V1
    class AuthController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/auth/login
      # body: { email: "test@test.com", password: "123456" }
      def login
        admin = Admin.find_by(email: params[:email].to_s.strip.downcase)
        unless admin&.valid_password?(params[:password])
          return render json: { code: 401, msg: "邮箱或密码错误" }, status: :unauthorized
        end

        verifier = ActiveSupport::MessageVerifier.new(token_secret, serializer: JSON)
        payload  = { admin_id: admin.id, email: admin.email, exp: 24.hours.from_now.to_i }
        token    = verifier.generate(payload)

        render json: {
          code: 200,
          msg: "登录成功",
          data: { token: token, expires_in: 86400 }
        }
      end

      private

      def token_secret
        Rails.application.secret_key_base[0..31] + "red_note_api_token_v1"
      end
    end
  end
end
