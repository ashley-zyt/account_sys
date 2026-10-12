module Api
  module V1
    # postforme 授权接口（供本地 agent 调用，走 auth/login 的 token 鉴权）。
    #
    # 与机器端回调 postforme/auth_callback 不同：这组接口不依赖 Account 记录，
    # 直接用 external_id 标识「谁的账号」。external_id 约定格式「所属人-平台-账号名」
    # （示例：张俊-youtube-美食号），具体怎么填由使用方自定，只要保证唯一即可。
    #
    # 授权是一次性异步流程：
    #   1. auth_url       生成授权链接（postforme 侧用 external_id 记下这次授权）
    #   2. 人工在浏览器完成 OAuth
    #   3. status / confirm 按 external_id 反查 social_account_id
    class PostformeAgentController < BaseController
      # POST /api/v1/postforme_agent/auth_url
      # body: { platform: "youtube", external_id: "张俊-youtube-美食号" }
      def auth_url
        platform    = params[:platform].to_s.strip
        external_id = params[:external_id].to_s.strip
        return render_error(msg: "platform 不能为空") if platform.blank?
        return render_error(msg: "external_id 不能为空") if external_id.blank?

        resp = PostformeApi.auth_url(platform: platform, external_id: external_id)
        unless PostformeApi.success?(resp)
          return render_error(msg: "获取授权链接失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        url = resp[:body].is_a?(Hash) ? resp[:body]['url'].to_s : ''
        return render_error(msg: "postforme 未返回授权链接", code: 502, status: :bad_gateway) if url.blank?

        render_success(data: { platform: platform, external_id: external_id, auth_url: url })
      end

      # GET /api/v1/postforme_agent/status?external_id=xxx
      def status
        external_id = params[:external_id].to_s.strip
        return render_error(msg: "external_id 不能为空") if external_id.blank?

        resp = PostformeApi.social_accounts(external_id: external_id)
        unless PostformeApi.success?(resp)
          return render_error(msg: "查询失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        connected = PostformeApi.items(resp).find { |a| a['status'] == 'connected' && a['id'].present? }
        if connected
          render_success(data: { external_id: external_id, auth_status: 'authorized', social_account_id: connected['id'] })
        else
          render_success(data: { external_id: external_id, auth_status: 'pending', social_account_id: nil })
        end
      end

      # POST /api/v1/postforme_agent/confirm
      # body: { external_id: "张俊-youtube-美食号" }
      def confirm
        external_id = params[:external_id].to_s.strip
        return render_error(msg: "external_id 不能为空") if external_id.blank?

        resp = PostformeApi.social_accounts(external_id: external_id)
        unless PostformeApi.success?(resp)
          return render_error(msg: "查询失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        connected = PostformeApi.items(resp).find { |a| a['status'] == 'connected' && a['id'].present? }
        return render_error(msg: "授权未完成，请先在浏览器完成 OAuth 后重试", code: 409, status: :conflict) unless connected

        render_success(data: { external_id: external_id, social_account_id: connected['id'] })
      end

      # POST /api/v1/postforme_agent/publish
      # body: {
      #   social_account_id: "spc_xxx",            # 必填，授权拿到的 social_account_id
      #   caption: "标题/正文",                     # 必填
      #   media_urls: ["https://.../x.mp4"],        # 可选，媒体公开 URL 数组（也支持逗号分隔字符串）
      #   external_id: "本系统任务标识",             # 可选，用于关联
      #   scheduled_at: "2026-01-01T12:00:00Z"      # 可选，定时发布（ISO8601 UTC）
      # }
      def publish
        social_account_id = params[:social_account_id].to_s.strip
        caption = params[:caption].to_s
        return render_error(msg: "social_account_id 不能为空") if social_account_id.blank?
        return render_error(msg: "caption 不能为空") if caption.blank?

        resp = PostformeApi.create_post(
          caption: caption,
          social_account_ids: [social_account_id],
          media_urls: parse_media_urls(params[:media_urls]),
          external_id: params[:external_id].presence,
          scheduled_at: params[:scheduled_at].presence
        )
        unless PostformeApi.success?(resp)
          return render_error(msg: "发布失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        post_id = resp[:body].is_a?(Hash) ? resp[:body]['id'].to_s : ''
        return render_error(msg: "postforme 未返回 post ID", code: 502, status: :bad_gateway) if post_id.blank?

        render_success(data: { post_id: post_id, social_account_id: social_account_id })
      end

      private

      # 兼容数组 / 逗号分隔字符串，转成干净的非空字符串数组
      def parse_media_urls(value)
        case value
        when Array  then value.map(&:to_s).map(&:strip).reject(&:blank?)
        when String then value.split(',').map(&:strip).reject(&:blank?)
        else []
        end
      end
    end
  end
end
