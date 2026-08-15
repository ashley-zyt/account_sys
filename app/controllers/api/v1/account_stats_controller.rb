module Api
  module V1
    # 账号统计数据接收接口
    # 接收外部系统推送的账号粉丝量、发帖量，自动基于现有 post_stats 聚合浏览/点赞/评论/分享
    class AccountStatsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/account_stats/batch_update
      #
      # 批量接收账号粉丝量、发帖量，自动基于现有 post_stats 数据聚合总浏览/总点赞/总评论/总分享
      # 注意：发文明细数据通过 post_stats 接口录入，本接口只更新统计快照
      #
      # 规则：
      #   - total_followers（粉丝数）：所有平台均使用传入值
      #   - total_posts（发帖量）：YouTube/Instagram 使用传入值，其他平台从 post_stats COUNT(*) 聚合
      #   - 总浏览/总点赞/总评论/总分享：始终从 post_stats 表现有数据聚合计算
      #
      # 请求体 JSON 格式：
      # {
      #   "results": [
      #     {
      #       "account_id": 295,
      #       "total_followers": 1000,
      #       "total_posts": 50
      #     }
      #   ]
      # }
      #
      # 返回格式：
      # {
      #   "code": 200,
      #   "msg": "处理完成",
      #   "data": {
      #     "total": 1,
      #     "success_count": 1,
      #     "failed_count": 0,
      #     "success": [295],
      #     "failed": []
      #   }
      # }
      def batch_update
        params_hash = parse_request_body
        results = extract_results(params_hash)

        unless results.is_a?(Array) && results.any?
          return render json: { code: 400, msg: "参数错误：results 数组不能为空" }, status: :bad_request
        end

        # 参数校验：每个 item 必须有有效的 account_id
        invalid_items = results.reject { |item| (item[:account_id] || item['account_id']).to_i > 0 }
        if invalid_items.any?
          return render json: { code: 400, msg: "参数错误：每个账号数据必须包含有效的 account_id（正整数）" }, status: :bad_request
        end

        result = PostDatas.update_account_stats!(results)

        render json: {
          code: 200,
          msg: "处理完成",
          data: {
            total: results.size,
            success_count: result[:success].size,
            failed_count: result[:failed].size,
            success: result[:success],
            failed: result[:failed]
          }
        }
      rescue JSON::ParserError => e
        Rails.logger.error "[Api::V1::AccountStats] JSON 解析失败: #{e.message}"
        render json: { code: 400, msg: "JSON 格式错误: #{e.message}" }, status: :bad_request
      rescue => e
        Rails.logger.error "[Api::V1::AccountStats] 批量更新异常: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
        render json: { code: 500, msg: "服务器内部错误: #{e.message}" }, status: :internal_server_error
      end

      private

      # 解析请求体
      def parse_request_body
        body = request.body.read
        Rails.logger.info "[Api::V1::AccountStats] 收到请求: #{body[0..2000]}"
        parsed = JSON.parse(body)
        parsed = parsed.with_indifferent_access if parsed.is_a?(Hash)
        parsed
      end

      # 从请求参数中提取 results 数组，支持 results/data 两种key
      def extract_results(params_hash)
        return [] unless params_hash.is_a?(Hash)
        results = params_hash[:results] || params_hash['results'] ||
                  params_hash[:data] || params_hash['data']
        return [] unless results.is_a?(Array)
        results
      end
    end
  end
end
