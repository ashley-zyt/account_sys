module Api
  module V1
    # 外部资源接入接口：供 grok_bot 等外部来源定时/每日推送图文/纯文字/视频资源。
    #
    # 鉴权：复用 auth/login 的 Bearer token（见 BaseController），资源入库后按主题存储，
    # 并按目标平台拆分生成 ExternalPublishTask 发布任务（pending），走系统统一调度发布。
    #
    # 接口：
    #   POST /api/v1/external_resources
    #   入参（application/json）：
    #     theme       主题名称（必填，须已存在于 Theme 表）
    #     media_type  媒体形态：video / image / text（必填）
    #     text        文字内容（可空；image/video 可带，text 必填）
    #     media_urls  媒体 URL 数组（image 多张 / video 1 个 / text 空）
    #     platforms   目标平台数组（可空，默认 ["twitter"]）
    class ExternalResourcesController < BaseController
      def create
        theme = params[:theme].to_s.strip
        media_type = params[:media_type].to_s.strip
        text = params[:text].to_s
        media_urls = Array(params[:media_urls]).map(&:to_s).reject(&:blank?)
        platforms = params[:platforms].present? ? Array(params[:platforms]).map(&:to_s).reject(&:blank?) : ['twitter']

        return render_error(msg: 'theme 必填') if theme.blank?
        return render_error(msg: 'media_type 必填') if media_type.blank?
        unless ExternalResource.media_types.key?(media_type)
          return render_error(msg: "media_type 非法：#{media_type}（仅支持 video/image/text）")
        end
        unless Theme.find_by(name: theme)
          return render_error(msg: "主题不存在：#{theme}")
        end

        # 媒体形态 × 资源数量校验
        case media_type
        when 'image'
          return render_error(msg: 'image 形态需要至少 1 张图片（media_urls）') if media_urls.empty?
        when 'video'
          return render_error(msg: 'video 形态需要且仅需 1 个视频（media_urls）') if media_urls.size != 1
        when 'text'
          return render_error(msg: 'text 形态需要 text 内容') if text.blank?
        end

        valid_platforms = ExternalPublishTask.platforms.keys
        platforms.each do |p|
          return render_error(msg: "平台非法：#{p}") unless valid_platforms.include?(p)
        end

        resource = nil
        tasks = []
        ActiveRecord::Base.transaction do
          resource = ExternalResource.create!(
            theme: theme,
            source: :grok_bot,
            media_type: media_type,
            text: text,
            media_urls: media_urls,
            platforms: platforms,
            status: :pending
          )

          platforms.each do |platform|
            tasks << ExternalPublishTask.create!(
              theme: theme,
              platform: platform,
              media_type: media_type,
              text: text,
              media_urls: media_urls,
              title: text.to_s.truncate(100),
              status: :pending,
              external_resource_id: resource.id
            )
          end

          resource.update!(status: :queued)
        end

        render_success(data: {
          resource_id: resource.id,
          created_count: tasks.size,
          task_ids: tasks.map(&:id)
        })
      rescue => e
        Rails.logger.error "[ExternalResources] 创建失败: #{e.message}"
        render_error(msg: "服务器错误：#{e.message}", code: 500, status: :internal_server_error)
      end
    end
  end
end
