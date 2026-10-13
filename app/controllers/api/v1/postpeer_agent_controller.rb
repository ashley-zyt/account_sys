module Api
  module V1
    # postpeer 授权接口（供本地 agent 调用，走 auth/login 的 token 鉴权）。
    #
    # 与机器端回调 postpeer/auth_callback 不同：这组接口不依赖 Account 记录，
    # 直接用 profile_id 标识「谁的账号」。postpeer 没有 external_id 概念，
    # 授权前先创建 profile（name 用 external_id），授权 URL 绑定 profileId，
    # 授权后按 profileId 反查 accountId（integration.id）。
    #
    # 授权是一次性异步流程：
    #   1. auth_url       创建 profile + 生成授权链接（返回 profile_id）
    #   2. 人工在浏览器完成 OAuth
    #   3. status / confirm 按 profile_id 反查 accountId
    #
    # 注意：postpeer 发布 X（twitter）消耗积分，仅支持 facebook/instagram/youtube/tiktok。
    class PostpeerAgentController < BaseController
      include OssSignedUrl

      SUPPORTED_PLATFORMS = %w[facebook instagram youtube tiktok].freeze
      DEFAULT_BUCKET = 'operation-viodes'.freeze

      # POST /api/v1/postpeer_agent/auth_url
      # body: { platform: "youtube", external_id: "张俊-youtube-美食号" }
      def auth_url
        platform    = params[:platform].to_s.strip
        external_id = params[:external_id].to_s.strip
        return render_error(msg: "platform 不能为空") if platform.blank?
        return render_error(msg: "external_id 不能为空") if external_id.blank?
        return render_error(msg: "postpeer 不支持该平台（仅 facebook/instagram/youtube/tiktok）") unless SUPPORTED_PLATFORMS.include?(platform)

        # 创建 profile（name 用 external_id，作为「谁的账号」标识）
        resp = PostpeerApi.create_profile(name: external_id)
        unless PostpeerApi.success?(resp)
          return render_error(msg: "创建 profile 失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end
        profile_id = resp[:body].is_a?(Hash) ? resp[:body].dig('profile', 'id').to_s : ''
        return render_error(msg: "postpeer 未返回 profile ID", code: 502, status: :bad_gateway) if profile_id.blank?

        resp = PostpeerApi.connect_url(platform: platform, profile_id: profile_id)
        unless PostpeerApi.success?(resp)
          return render_error(msg: "获取授权链接失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        url = resp[:body].is_a?(Hash) ? resp[:body]['url'].to_s : ''
        return render_error(msg: "postpeer 未返回授权链接", code: 502, status: :bad_gateway) if url.blank?

        render_success(data: { platform: platform, external_id: external_id, profile_id: profile_id, auth_url: url })
      end

      # GET /api/v1/postpeer_agent/status?profile_id=xxx
      def status
        profile_id = params[:profile_id].to_s.strip
        return render_error(msg: "profile_id 不能为空") if profile_id.blank?

        resp = PostpeerApi.integrations(profile_id: profile_id)
        unless PostpeerApi.success?(resp)
          return render_error(msg: "查询失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        integration = PostpeerApi.integration_items(resp).first
        if integration && integration['id'].present?
          render_success(data: { profile_id: profile_id, auth_status: 'authorized', peer_account_id: integration['id'] })
        else
          render_success(data: { profile_id: profile_id, auth_status: 'pending', peer_account_id: nil })
        end
      end

      # POST /api/v1/postpeer_agent/confirm
      # body: { profile_id: "..." }
      def confirm
        profile_id = params[:profile_id].to_s.strip
        return render_error(msg: "profile_id 不能为空") if profile_id.blank?

        resp = PostpeerApi.integrations(profile_id: profile_id)
        unless PostpeerApi.success?(resp)
          return render_error(msg: "查询失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        integration = PostpeerApi.integration_items(resp).first
        return render_error(msg: "授权未完成，请先在浏览器完成 OAuth 后重试", code: 409, status: :conflict) unless integration && integration['id'].present?

        render_success(data: { profile_id: profile_id, peer_account_id: integration['id'] })
      end

      # POST /api/v1/postpeer_agent/publish
      # 媒体支持两种来源，可混用：media_urls（线上链接）/ media_files（本地文件上传）
      def publish
        peer_account_id = params[:peer_account_id].to_s.strip
        platform        = params[:platform].to_s.strip
        caption         = params[:caption].to_s
        return render_error(msg: "peer_account_id 不能为空") if peer_account_id.blank?
        return render_error(msg: "platform 不能为空") if platform.blank?
        return render_error(msg: "caption 不能为空") if caption.blank?
        return render_error(msg: "postpeer 不支持该平台（仅 facebook/instagram/youtube/tiktok）") unless SUPPORTED_PLATFORMS.include?(platform)

        media_urls = parse_media_urls(params[:media_urls])
        uploaded = upload_media_files(params[:media_files])
        return render_error(msg: "媒体文件上传失败，请稍后重试", code: 502, status: :bad_gateway) if uploaded == :failed
        media_urls.concat(uploaded)

        resp = PostpeerApi.create_post(
          content: caption,
          platform: platform,
          account_id: peer_account_id,
          media_urls: media_urls
        )
        unless PostpeerApi.success?(resp)
          return render_error(msg: "发布失败：#{resp[:raw]}", code: 502, status: :bad_gateway)
        end

        post_id = resp[:body].is_a?(Hash) ? resp[:body]['postId'].to_s : ''
        return render_error(msg: "postpeer 未返回 post ID", code: 502, status: :bad_gateway) if post_id.blank?

        render_success(data: { post_id: post_id, peer_account_id: peer_account_id })
      end

      private

      def parse_media_urls(value)
        case value
        when Array  then value.map(&:to_s).map(&:strip).reject(&:blank?)
        when String then value.split(',').map(&:strip).reject(&:blank?)
        else []
        end
      end

      def upload_media_files(files)
        return [] if files.blank?
        list = files.is_a?(Array) ? files : [files]
        urls = list.map { |f| upload_one_file(f) }
        return :failed if urls.any?(&:nil?)
        urls
      end

      def upload_one_file(file)
        return nil unless file.respond_to?(:tempfile) && file.tempfile

        require 'fileutils'
        ext = File.extname(file.original_filename.to_s)
        tmp_path = File.join(Dir.tmpdir, "postpeer_media_#{SecureRandom.uuid}#{ext}")

        begin
          FileUtils.cp(file.tempfile.path, tmp_path)
          result = upload_local_file_to_oss(tmp_path, DEFAULT_BUCKET)
          result[:ok] ? result[:signed_url] : nil
        ensure
          File.delete(tmp_path) if File.exist?(tmp_path)
        end
      rescue => e
        Rails.logger.error "[PostpeerAgent] 上传媒体文件失败: #{e.class} #{e.message}"
        nil
      end
    end
  end
end
