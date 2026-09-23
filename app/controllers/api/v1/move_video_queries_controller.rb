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

        videos = MoveVideo.where(id: start_id..end_id)
                          .where(status: MoveVideo.statuses[:downloaded], jianying_status: MoveVideo.jianying_statuses[:pending])
                          .order(:id)

        data = videos.map do |v|
          {
            id: v.id,
            source_video_url: v.source_video_url,
            source_account_url: v.source_account_url,
            theme: v.theme,
            group_id: v.group_id,
            platforms: v.platforms,
            # 对外返回旧单状态机字符串（legacy_status 做双状态 → 旧状态映射），
            # 保证外部客户端 `status == "pending_process"` 的过滤仍然成立。
            status: v.legacy_status,
            raw_oss_url: v.raw_oss_url,
            # 成片 OSS URL 已迁到 move_task.oss_url；本接口只返回「待剪映」记录，尚未成片，恒为 null
            processed_oss_url: nil,
            error_msg: v.error_msg,
            # 时间统一 ISO8601（带时区），兼容外部 Time.parse
            download_started_at: v.download_started_at&.iso8601,
            downloaded_at: v.downloaded_at&.iso8601,
            process_started_at: v.process_started_at&.iso8601,
            processed_at: v.processed_at&.iso8601,
            created_at: v.created_at&.iso8601,
            updated_at: v.updated_at&.iso8601
          }
        end

        render_success(msg: "查询成功，共 #{data.size} 条记录", data: data)
      end
    end
  end
end
