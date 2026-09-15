module Api
  module V1
    # 浏览器占用状态回传接口 —— 供采集端/运营机器在真正用完指纹浏览器后，
    # 主动回传「已释放」，让占用中心精确释放（比 ttl 兜底更准）。
    class BrowserOccupationsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/browser_occupations/release
      # 入参：profile_name（与机器端共通的指纹浏览器名）；或直接传 resource_key（内部调试用）
      def release
        resource_key = params[:resource_key].to_s.strip
        profile_name = params[:profile_name].to_s.strip
        if resource_key.blank? && profile_name.present?
          resource_key = BrowserOccupation.key_for_profile(profile_name)
        end
        if resource_key.blank?
          return render json: { type: 'error', message: 'profile_name 或 resource_key 不能为空' }
        end

        occupation = BrowserOccupationManager.release_by_resource_key(resource_key)
        if occupation
          render json: { type: 'success', message: '已释放占用', data: { resource_key: resource_key, profile_name: profile_name.presence } }
        else
          render json: { type: 'success', message: '无活跃占用，无需释放', data: { resource_key: resource_key, profile_name: profile_name.presence } }
        end
      end
    end
  end
end
