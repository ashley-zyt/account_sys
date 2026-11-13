module Api
  module V1
    # X（Twitter）图文 / 纯文字 发布接口：供外部直接调用，与系统内任务体系完全独立。
    #
    # 鉴权：复用 auth/login 的 Bearer token（见 BaseController#authenticate_token!），
    #   X 的 access_token 由系统内部管理（XAuthService.access_token_for），外部无需关心。
    #
    # 接口：
    #   POST /api/v1/x_posts
    #   入参（multipart/form-data）：
    #     account_id   本系统已授权 X 的账号 ID（必填，二选一）
    #     account_name 账号名（必填，二选一，优先 account_id）
    #     text         推文文字（可空，纯图片时留空；纯文字时填文字）
    #     images[]     本地图片文件（可多张，可空；与 text 至少提供一个）
    #
    # 流程：找账号 → 取 token → 逐张图片简单上传拿 media_id → create_tweet。
    # 返回 tweet_id，不回执、不建任务、不写 task_log。
    class XPostsController < BaseController
      # 单条推最多 4 张图
      MAX_IMAGES = 4

      def create
        account = find_account
        return if performed?

        text = params[:text].to_s
        images = normalize_images(params[:images])
        if text.blank? && images.empty?
          return render_error(msg: "text 和 images 至少提供一个")
        end
        if images.size > MAX_IMAGES
          return render_error(msg: "单条推最多 #{MAX_IMAGES} 张图片")
        end

        token = XAuthService.access_token_for(account)
        return render_error(msg: "获取 X access_token 失败（请重新认证）") if token.blank?

        media_ids = upload_images(token, images)
        return if performed?

        resp = XApi.create_tweet(access_token: token, text: text, media_ids: media_ids)
        unless XApi.success?(resp)
          Rails.logger.error "[XPosts] 发推失败 account=#{account.id}: #{resp[:raw]}"
          return render_error(msg: "X 发推失败：#{XApi.extract_error(resp)}", code: 502, status: :bad_gateway)
        end

        tweet_id = resp[:body].is_a?(Hash) ? resp[:body].dig('data', 'id').to_s : ''
        render_success(data: { account_id: account.id, tweet_id: tweet_id, media_ids: media_ids })
      end

      private

      def find_account
        if params[:account_id].present?
          account = Account.find_by(id: params[:account_id])
        elsif params[:account_name].present?
          account = Account.find_by(account_name: params[:account_name].to_s.strip)
        else
          render_error(msg: "account_id 或 account_name 必填")
          return nil
        end

        unless account
          render_error(msg: "账号不存在")
          return nil
        end
        unless account.x_credential&.authorized?
          render_error(msg: "账号 #{account.id} 未授权 X（auth_status=#{account.x_credential&.auth_status}）")
          return nil
        end
        account
      end

      def normalize_images(value)
        return [] if value.blank?
        value.is_a?(Array) ? value : [value]
      end

      # 逐张上传图片，返回 media_id 数组；失败时已通过 render_error 响应并返回 nil
      def upload_images(token, images)
        ids = []
        images.each_with_index do |file, i|
          unless file.respond_to?(:read)
            render_error(msg: "images[#{i}] 不是有效文件")
            return nil
          end

          data = file.read
          content_type = file.respond_to?(:content_type) ? file.content_type.to_s.presence : 'image/png'
          content_type = 'image/png' if content_type.blank?
          filename = file.respond_to?(:original_filename) ? File.basename(file.original_filename.to_s) : "image#{i + 1}.png"

          resp = XApi.media_upload_image(access_token: token, data: data, content_type: content_type, filename: filename)
          unless XApi.success?(resp)
            Rails.logger.error "[XPosts] 图片上传失败 account=#{params[:account_id]} index=#{i}: #{resp[:raw]}"
            render_error(msg: "第 #{i + 1} 张图片上传失败：#{XApi.extract_error(resp)}", code: 502, status: :bad_gateway)
            return nil
          end

          media_id = resp[:body].is_a?(Hash) ? resp[:body].dig('data', 'id').to_s : ''
          if media_id.blank?
            render_error(msg: "第 #{i + 1} 张图片上传未返回 media_id", code: 502, status: :bad_gateway)
            return nil
          end
          ids << media_id
        end
        ids
      end
    end
  end
end
