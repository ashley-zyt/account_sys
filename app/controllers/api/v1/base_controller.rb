module Api
  module V1
    class BaseController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_token!

      private

      TOKEN_SECRET = "red_note_api_token_v1".freeze
      TOKEN_TTL    = 24.hours

      def authenticate_token!
        header = request.headers["Authorization"].to_s
        token  = header.gsub(/\ABearer\s+/, "")
        return render_unauthorized("缺少 Token") if token.blank?

        payload = decode_token(token)
        return render_unauthorized("Token 无效或已过期") unless payload

        @current_admin = Admin.find_by(id: payload[:admin_id])
        return render_unauthorized("管理员不存在") unless @current_admin
      end

      def decode_token(token)
        verifier = ActiveSupport::MessageVerifier.new(token_secret, serializer: JSON)
        data     = verifier.verify(token)
        data.deep_symbolize_keys!
        return nil unless data[:exp].to_i > Time.now.to_i

        data
      rescue
        nil
      end

      def generate_token(admin)
        payload = { admin_id: admin.id, email: admin.email, exp: TOKEN_TTL.from_now.to_i }
        verifier = ActiveSupport::MessageVerifier.new(token_secret, serializer: JSON)
        verifier.generate(payload)
      end

      def token_secret
        Rails.application.secret_key_base[0..31] + TOKEN_SECRET
      end

      def render_unauthorized(msg = "Unauthorized")
        render json: { code: 401, msg: msg }, status: :unauthorized
      end

      def render_success(data: nil, msg: "success")
        resp = { code: 200, msg: msg }
        resp[:data] = data if data
        render json: resp
      end

      def render_error(msg:, code: 400, status: :bad_request)
        render json: { code: code, msg: msg }, status: status
      end
    end
  end
end
