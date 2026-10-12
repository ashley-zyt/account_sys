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
      include OssSignedUrl

      # 本地视频上传到的 OSS bucket（与 oss/upload_signature 默认一致）
      DEFAULT_BUCKET = 'operation-viodes'.freeze

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
      # 媒体支持两种来源，可混用：
      #   media_urls  ：线上公开链接（JSON 数组，或逗号分隔字符串）
      #   media_files ：本地文件（multipart 上传，服务端先传到 OSS 再拿链接）
      # body（JSON 形式，仅用链接时）:
      #   social_account_id: "spc_xxx",            # 必填，授权拿到的 social_account_id
      #   caption: "标题/正文",                     # 必填
      #   media_urls: ["https://.../x.mp4"],        # 可选，媒体公开 URL 数组
      #   external_id: "本系统任务标识",             # 可选，用于关联
      #   scheduled_at: "2026-01-01T12:00:00Z"      # 可选，定时发布（ISO8601 UTC）
      # multipart 形式（传本地文件时）: social_account_id / caption / media_files 等为表单字段
      def publish
        social_account_id = params[:social_account_id].to_s.strip
        caption = params[:caption].to_s
        return render_error(msg: "social_account_id 不能为空") if social_account_id.blank?
        return render_error(msg: "caption 不能为空") if caption.blank?

        # 媒体：直接传的线上链接 + 本地文件上传后得到的 OSS 链接
        media_urls = parse_media_urls(params[:media_urls])
        uploaded = upload_media_files(params[:media_files])
        return render_error(msg: "媒体文件上传失败，请稍后重试", code: 502, status: :bad_gateway) if uploaded == :failed
        media_urls.concat(uploaded)

        resp = PostformeApi.create_post(
          caption: caption,
          social_account_ids: [social_account_id],
          media_urls: media_urls,
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

      # 本地文件（multipart）逐个上传 OSS，返回签名 URL 数组；任一失败返回 :failed
      def upload_media_files(files)
        return [] if files.blank?
        list = files.is_a?(Array) ? files : [files]
        urls = list.map { |f| upload_one_file(f) }
        return :failed if urls.any?(&:nil?)
        urls
      end

      # 单个 UploadedFile 上传到 OSS，返回签名 URL（失败返回 nil）
      def upload_one_file(file)
        return nil unless file.respond_to?(:tempfile) && file.tempfile

        require 'fileutils'
        # 复制到带原始扩展名的临时文件（OSS key 用 UUID + 扩展名，避免丢扩展名导致 postforme 无法识别）
        ext = File.extname(file.original_filename.to_s)
        tmp_path = File.join(Dir.tmpdir, "postforme_media_#{SecureRandom.uuid}#{ext}")

        begin
          FileUtils.cp(file.tempfile.path, tmp_path)
          result = upload_local_file_to_oss(tmp_path, DEFAULT_BUCKET)
          result[:ok] ? result[:signed_url] : nil
        ensure
          File.delete(tmp_path) if File.exist?(tmp_path)
        end
      rescue => e
        Rails.logger.error "[PostformeAgent] 上传媒体文件失败: #{e.class} #{e.message}"
        nil
      end
    end
  end
end
