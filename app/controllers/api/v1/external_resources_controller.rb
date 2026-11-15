module Api
  module V1
    # 外部资源接入接口：供 grok_bot 等外部来源定时/每日推送图文/纯文字/视频资源。
    #
    # 鉴权：复用 auth/login 的 Bearer token（见 BaseController），资源入库后按主题存储，
    # 并按目标平台拆分生成 ExternalPublishTask 发布任务，走系统统一调度发布。
    #
    # 两种模式：
    #   1. 存储待调度（默认）：不传 account_id，任务置 pending，等调度器分配账号后发布。
    #   2. 存储后立即发布：传 account_id，任务直接绑定该账号并置 waiting_publish，随后异步触发发布。
    #      —— 落库记录照常保留（ExternalResource + ExternalPublishTask + TaskLog），便于追溯发布结果。
    #
    # 接口：
    #   POST /api/v1/external_resources
    #   入参（application/json）：
    #     theme       主题名称（必填，须已存在于 Theme 表）
    #     media_type  媒体形态：video / image / text（必填）
    #     text        文字内容（可空；image/video 可带，text 必填）
    #     media_urls  媒体 URL 数组（image 多张 / video 1 个 / text 空）
    #     platforms   目标平台数组（可空，默认 ["twitter"]；传 account_id 时忽略，改用账号平台）
    #     account_id  账号 ID（可选；传入则存储后立即发布）
    class ExternalResourcesController < BaseController
      include OssSignedUrl

      # 本地文件上传到 OSS 的 bucket（按媒体形态区分：图片 → grok-images，视频 → grok-videos）
      IMAGE_BUCKET = 'grok-images'.freeze
      VIDEO_BUCKET = 'grok-videos'.freeze

      def create
        theme = params[:theme].to_s.strip
        media_type = params[:media_type].to_s.strip
        text = params[:text].to_s
        media_urls = Array(params[:media_urls]).map(&:to_s).reject(&:blank?)

        account = resolve_account
        return if performed?

        # 指定账号时目标平台固定为该账号平台（单平台即时发布）；否则按入参 platforms
        platforms = if account
                      [account.platform.to_s]
                    else
                      params[:platforms].present? ? Array(params[:platforms]).map(&:to_s).reject(&:blank?) : ['twitter']
                    end

        return render_error(msg: 'theme 必填') if theme.blank?
        return render_error(msg: 'media_type 必填') if media_type.blank?
        unless ExternalResource.media_types.key?(media_type)
          return render_error(msg: "media_type 非法：#{media_type}（仅支持 video/image/text）")
        end
        unless Theme.find_by(name: theme)
          return render_error(msg: "主题不存在：#{theme}")
        end

        # 本地文件（multipart）上传 OSS 并合并进 media_urls（与 media_urls 入参并存）
        uploaded = upload_media_files(params[:media_files], media_type)
        return render_error(msg: "媒体文件上传失败，请稍后重试", code: 502, status: :bad_gateway) if uploaded == :failed
        media_urls.concat(uploaded)

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
              status: account ? :waiting_publish : :pending,
              account_id: account&.id,
              browser_id: account&.browser_id,
              external_resource_id: resource.id
            )
          end

          resource.update!(status: :queued)
        end

        # 存储后立即发布：事务提交后再异步触发，避免事务内发起网络/发布
        publish_async(tasks.map(&:id)) if account

        render_success(data: {
          resource_id: resource.id,
          created_count: tasks.size,
          task_ids: tasks.map(&:id),
          immediate: account.present?
        })
      rescue => e
        Rails.logger.error "[ExternalResources] 创建失败: #{e.message}"
        render_error(msg: "服务器错误：#{e.message}", code: 500, status: :internal_server_error)
      end

      # 查询资源及其发布任务的状态与结果（按 resource_id）
      def show
        resource = ExternalResource.find_by(id: params[:id])
        return render_error(msg: "资源不存在：#{params[:id]}", code: 404, status: :not_found) unless resource

        tasks = resource.external_publish_tasks.order(:id).map do |task|
          {
            id: task.id,
            task_uuid: task.task_uuid,
            platform: task.platform,
            media_type: task.media_type,
            status: task.status,
            failure_count: task.failure_count,
            error_msg: task.error_msg,
            account_id: task.account_id,
            browser_id: task.browser_id,
            start_at: task.start_at,
            actual_publish_time: task.actual_publish_time,
            created_at: task.created_at,
            logs: task.task_logs.order(:id).map do |log|
              {
                publish_channel: log.publish_channel,
                status: log.status,
                error_msg: log.error_msg,
                run_at: log.run_at
              }
            end
          }
        end

        render_success(data: {
          id: resource.id,
          theme: resource.theme,
          source: resource.source,
          media_type: resource.media_type,
          text: resource.text,
          media_urls: resource.media_urls,
          platforms: resource.platforms,
          status: resource.status,
          created_at: resource.created_at,
          tasks: tasks
        })
      end

      private

      # 本地文件（multipart）逐个上传 OSS，返回签名 URL 数组；任一失败返回 :failed
      def upload_media_files(files, media_type)
        return [] if files.blank?
        list = files.is_a?(Array) ? files : [files]
        bucket = oss_bucket_for(media_type)
        urls = list.map { |f| upload_one_file(f, bucket) }
        return :failed if urls.any?(&:nil?)
        urls
      end

      # 单个 UploadedFile 上传到 OSS，返回签名 URL（失败返回 nil）
      def upload_one_file(file, bucket)
        return nil unless file.respond_to?(:tempfile) && file.tempfile

        require 'fileutils'
        ext = File.extname(file.original_filename.to_s)
        tmp_path = File.join(Dir.tmpdir, "external_resource_#{SecureRandom.uuid}#{ext}")

        begin
          FileUtils.cp(file.tempfile.path, tmp_path)
          result = upload_local_file_to_oss(tmp_path, bucket)
          result[:ok] ? result[:signed_url] : nil
        ensure
          File.delete(tmp_path) if File.exist?(tmp_path)
        end
      rescue => e
        Rails.logger.error "[ExternalResources] 上传媒体文件失败: #{e.class} #{e.message}"
        nil
      end

      def oss_bucket_for(media_type)
        media_type.to_s == 'video' ? VIDEO_BUCKET : IMAGE_BUCKET
      end

      def resolve_account
        return nil if params[:account_id].blank?

        account = Account.find_by(id: params[:account_id])
        unless account
          render_error(msg: "账号不存在：#{params[:account_id]}")
          return nil
        end
        account
      end

      # 异步触发立即发布：复用 PublishScheduler.attempt_task 走渠道链路由，
      # 图文/纯文字经 XPublisher 同步发推，视频经 XPublisher 异步上传（XPostPoller 回写）。
      def publish_async(task_ids)
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            task_ids.each do |id|
              task = ExternalPublishTask.find_by(id: id)
              next unless task

              begin
                PublishScheduler.attempt_task(task)
              rescue => e
                Rails.logger.error "[ExternalResources] 立即发布任务 ##{id} 异常: #{e.message}"
              end
            end
          end
        end
      end
    end
  end
end
