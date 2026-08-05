module Api
  module V1
    class MoveVideoQueriesController < BaseController

      # GET /api/v1/move_video_queries?start_id=1&end_id=100
      # 按ID范围查询搬运视频数据
      def index
        start_id = params[:start_id].to_i
        end_id   = params[:end_id].to_i

        if start_id <= 0 || end_id <= 0 || start_id > end_id
          return render_error(msg: "start_id 和 end_id 必须为正整数，且 start_id <= end_id")
        end

        videos = MoveVideo.where(id: start_id..end_id).order(:id)

        data = videos.map do |v|
          {
            id: v.id,
            source_video_url: v.source_video_url,
            source_account_url: v.source_account_url,
            theme: v.theme,
            group_id: v.group_id,
            platforms: v.platforms,
            status: v.status,
            # human_status: v.human_status,
            raw_oss_url: v.raw_oss_url,
            # processed_oss_url: v.processed_oss_url,
            error_msg: v.error_msg,
            download_started_at: v.download_started_at&.strftime("%Y-%m-%d %H:%M:%S"),
            downloaded_at: v.downloaded_at&.strftime("%Y-%m-%d %H:%M:%S"),
            # process_started_at: v.process_started_at&.strftime("%Y-%m-%d %H:%M:%S"),
            # processed_at: v.processed_at&.strftime("%Y-%m-%d %H:%M:%S"),
            created_at: v.created_at&.strftime("%Y-%m-%d %H:%M:%S"),
            updated_at: v.updated_at&.strftime("%Y-%m-%d %H:%M:%S")
          }
        end

        render_success(msg: "查询成功，共 #{data.size} 条记录", data: data)
      end
    end
  end
end
