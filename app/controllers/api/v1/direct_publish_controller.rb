module Api
  module V1
    # 外部直发接口：外部 agent 按本系统 account_id 直接发布（不建任务，落 direct_publish_log 记录）。
    #
    # 渠道路由：twitter → x_api；其它平台 → 按已授权渠道（postforme 优先，其次 postpeer）。
    # 支持文字/图文/视频。鉴权复用 auth/login 的 Bearer token。
    class DirectPublishController < BaseController
      include OssSignedUrl

      EXTERNAL_BUCKET = 'account-agic'.freeze
      EXTERNAL_PREFIX = 'external/'.freeze
      MAX_IMAGES = 4

      def create
        account = resolve_account
        return if performed?

        media_type = params[:media_type].to_s.strip
        text = params[:text].to_s
        title = params[:title].to_s.strip
        description = params[:description].to_s
        media_urls = Array(params[:media_urls]).map(&:to_s).reject(&:blank?)

        return render_error(msg: 'media_type 必填') if media_type.blank?
        unless %w[video image text].include?(media_type)
          return render_error(msg: "media_type 非法：#{media_type}（仅支持 video/image/text）")
        end

        uploaded = upload_media_files(params[:media_files])
        return render_error(msg: "媒体文件上传失败，请稍后重试", code: 502, status: :bad_gateway) if uploaded == :failed
        media_urls.concat(uploaded)

        case media_type
        when 'image'
          return render_error(msg: 'image 形态需要至少 1 张图片') if media_urls.empty?
          return render_error(msg: "image 形态最多 #{MAX_IMAGES} 张图片") if media_urls.size > MAX_IMAGES
        when 'video'
          return render_error(msg: 'video 形态需要且仅需 1 个视频') if media_urls.size != 1
        when 'text'
          return render_error(msg: 'text 形态需要 text 内容') if text.blank?
        end

        channel = resolve_channel(account)
        return render_error(msg: "账号 #{account.account_name} 无可用发布渠道（x_api/postforme/postpeer 均未授权）") unless channel

        resolved_urls = media_urls.map { |u| XPublisher.resolve_media_url(u, media_type) }
        result = publish(account, channel, media_type, text, title, description, resolved_urls)

        log_status = result[:log_status] || (result[:success] ? :success : :failed)

        log = DirectPublishLog.create!(
          account_id: account.id,
          platform: account.platform,
          media_type: media_type,
          publish_channel: channel,
          text: text,
          title: title.presence,
          description: description.presence,
          media_urls: media_urls,
          status: log_status,
          error_msg: result[:success] ? nil : result[:message],
          external_id: result[:external_id]
        )

        # X 视频：上传成功后记录 XPost，由 XPostPoller 异步发推并回写本记录
        if result[:xpost_media_id].present?
          XPost.create!(task: log, media_id: result[:xpost_media_id], status: :processing)
        end

        if result[:success]
          render_success(msg: result[:message] || '发布成功')
        else
          render_error(msg: result[:message], code: 502, status: :bad_gateway)
        end
      rescue => e
        Rails.logger.error "[DirectPublish] 发布异常: #{e.message}"
        render_error(msg: "服务器错误：#{e.message}", code: 500, status: :internal_server_error)
      end

      private

      def resolve_account
        account_id = params[:account_id].to_i
        if account_id <= 0
          render_error(msg: 'account_id 必填')
          return nil
        end
        account = Account.find_by(id: account_id)
        unless account
          render_error(msg: "账号不存在：#{account_id}")
          return nil
        end
        account
      end

      def resolve_channel(account)
        if account.platform.to_s == 'twitter'
          return 'x_api' if account.x_credential&.authorized?
        else
          return 'postforme' if account.postforme_account&.authorized?
          return 'postpeer' if account.postpeer_account&.authorized?
        end
        nil
      end

      def publish(account, channel, media_type, text, title, description, media_urls)
        case channel
        when 'x_api' then publish_x(account, media_type, text, media_urls)
        when 'postforme' then publish_postforme(account, media_type, text, title, description, media_urls)
        when 'postpeer' then publish_postpeer(account, media_type, text, title, description, media_urls)
        end
      end

      def publish_x(account, media_type, text, media_urls)
        token = XAuthService.access_token_for(account)
        return { success: false, message: '无法获取 X access_token（请重新认证）' } if token.blank?

        if media_type == 'video'
          result = XPublisher.upload_video(token, media_urls.first)
          return result unless result[:success]
          { success: true, message: "已提交 X 视频上传（media_id=#{result[:media_id]}），异步发布中", external_id: result[:media_id], log_status: :pending, xpost_media_id: result[:media_id] }
        end

        media_ids = []
        media_urls.each do |url|
          uploaded = XPublisher.upload_image_from_url(token, url)
          return uploaded unless uploaded[:success]
          media_ids << uploaded[:media_id]
        end

        resp = XApi.create_tweet(access_token: token, text: text, media_ids: media_ids)
        unless XApi.success?(resp)
          return { success: false, message: "发推失败：#{XApi.extract_error(resp)}" }
        end

        tweet_id = resp[:body].is_a?(Hash) ? resp[:body].dig('data', 'id').to_s : ''
        { success: true, message: '发布成功', external_id: tweet_id }
      end

      def publish_postforme(account, media_type, text, title, description, media_urls)
        pa = account.postforme_account
        return { success: false, message: '账号未授权 postforme' } unless pa&.authorized?

        caption = text.presence || title.presence || ''
        platform_configurations = nil
        if account.platform.to_s == 'youtube' && (title.present? || description.present?)
          platform_configurations = { 'youtube' => { 'title' => title.presence, 'description' => description.presence }.compact }
        end

        resp = PostformeApi.create_post(
          caption: caption,
          social_account_ids: [pa.social_account_id],
          media_urls: media_urls,
          platform_configurations: platform_configurations
        )
        unless PostformeApi.success?(resp)
          return { success: false, message: "postforme 发布失败：#{resp[:raw]}" }
        end

        post_id = resp[:body].is_a?(Hash) ? resp[:body]['id'].to_s : ''
        { success: true, message: '发布成功', external_id: post_id }
      end

      def publish_postpeer(account, media_type, text, title, description, media_urls)
        pa = account.postpeer_account
        return { success: false, message: '账号未授权 postpeer' } unless pa&.authorized?

        content = description.presence || text.presence || title.presence || ''
        platform_specific_data = nil
        if account.platform.to_s == 'youtube' && title.present?
          platform_specific_data = { 'title' => title }
        end

        resp = PostpeerApi.create_post(
          content: content,
          platform: account.platform,
          account_id: pa.peer_account_id,
          media_urls: media_urls,
          media_type: media_type == 'image' ? 'image' : 'video',
          platform_specific_data: platform_specific_data
        )
        unless PostpeerApi.success?(resp)
          return { success: false, message: "postpeer 发布失败：#{resp[:raw]}" }
        end

        post_id = resp[:body].is_a?(Hash) ? resp[:body]['postId'].to_s : ''
        { success: true, message: '发布成功', external_id: post_id }
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
        ext = File.extname(file.original_filename.to_s)
        key = "#{EXTERNAL_PREFIX}#{SecureRandom.uuid}#{ext}"
        OssTransfer.hk_client.get_bucket(EXTERNAL_BUCKET).put_object(key, file: file.tempfile.path)
        key
      rescue => e
        Rails.logger.error "[DirectPublish] 上传 OSS 失败: #{e.class} #{e.message}"
        nil
      end
    end
  end
end
