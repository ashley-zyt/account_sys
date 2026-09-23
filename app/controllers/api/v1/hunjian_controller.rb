module Api
  module V1
    # 搬运混剪接口：混剪程序认领「待混剪」源视频 + 回传混剪成品。
    #
    # 流程：
    #   fetch_pending   混剪程序一次性认领一大批待混剪源视频（原子置「混剪中」）
    #   report_result   混剪程序回传成品（2 个源视频 + 成品 oss_url + 标题）→ 按平台建 hunjian_task + 源视频置「已完成」
    class HunjianController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/hunjian/fetch_pending
      # 入参：limit（可选，默认 100，最大 500）
      def fetch_pending
        limit = (params[:limit].presence || 100).to_i.clamp(1, 500)
        claimed = MoveVideo.claim_hunjian_batch!(limit: limit)
        render_success(data: {
          count: claimed.size,
          items: claimed.map { |v| build_item(v) }
        })
      end

      # POST /api/v1/hunjian/report_result
      # 入参：move_video_ids(两个源视频 id 数组)、oss_url、title、description(可选)、platforms(可选)
      # 处理：源视频置「混剪完成」+ 按平台各建一条 hunjian_task
      def report_result
        move_video_ids = params[:move_video_ids]
        move_video_ids = JSON.parse(move_video_ids) if move_video_ids.is_a?(String)
        unless move_video_ids.is_a?(Array) && move_video_ids.map(&:to_i).uniq.size == 2
          return render_error('move_video_ids 必须是两个不同的源视频 id')
        end

        videos = move_video_ids.map { |id| MoveVideo.find_by(id: id.to_i) }
        return render_error('两个 move_video 必须都存在') if videos.any?(&:nil?)

        oss_url = params[:oss_url].to_s.strip
        title   = params[:title].to_s.strip
        return render_error('oss_url 不能为空') if oss_url.blank?
        return render_error('title 不能为空') if title.blank?

        description = params[:description].to_s.strip
        platforms_str = params[:platforms].to_s.strip
        platforms_str = videos.first.platforms.to_s if platforms_str.blank?
        theme = videos.first.theme.to_s

        count = 0
        MoveVideo.transaction do
          # 源视频置「混剪完成」（幂等：已是完成的跳过，重复回传不报错）
          videos.each do |v|
            v.update!(hunjian_status: :completed, error_msg: nil) unless v.hunjian_completed?
          end
          count = HunjianTask.create_from_hunjian_result!(
            move_video_ids: move_video_ids.map(&:to_i),
            oss_url: oss_url,
            title: title,
            description: description,
            platforms: platforms_str,
            theme: theme
          )
        end

        render_success(message: "混剪完成已记录，已创建 #{count} 条发布任务")
      rescue => e
        Rails.logger.error "[Hunjian] 回传混剪结果异常: #{e.message}"
        render_error(e.message)
      end

      private

      def build_item(video)
        {
          id: video.id,
          raw_oss_url: video.raw_oss_url,
          theme: video.theme,
          group_id: video.group_id,
          source_title: video.source_title,
          platforms: video.platforms
        }
      end

      def render_success(data: nil, message: 'success')
        resp = { type: 'success' }
        resp[:data] = data if data
        resp[:message] = message
        render json: resp
      end

      def render_error(message)
        render json: { type: 'error', message: message }
      end
    end
  end
end
