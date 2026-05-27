module Api
  module V1
    # 发文数据接收接口
    # 接收外部系统推送的账号发文数据
    class PostStatsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # POST /api/v1/post_stats
      # 请求参数:
      # {
      #   account_id: 1,
      #   post_date: "2025-05-01",
      #   title: "发文标题",
      #   url: "https://...",
      #   likes_count: 100,
      #   shares_count: 20,
      #   comments_count: 15,
      #   views_count: 1000,
      #   data_updated_at: "2025-05-01 12:00:00"
      # }
      def create
        # 参数校验
        if params[:account_id].blank?
          return render json: { code: 400, msg: 'account_id 不能为空' }, status: :bad_request
        end

        if params[:post_date].blank?
          return render json: { code: 400, msg: 'post_date 不能为空' }, status: :bad_request
        end

        if params[:url].blank?
          return render json: { code: 400, msg: 'url 不能为空' }, status: :bad_request
        end

        # 查找对应账号
        account = Account.find_by(id: params[:account_id])
        if account.blank?
          return render json: { code: 404, msg: "账号ID[#{params[:account_id]}]不存在" }, status: :not_found
        end

        # 检查 url 是否已存在（不可重复）
        existing = PostStat.find_by(url: params[:url])
        if existing
          return render json: { code: 409, msg: "url 已存在，不允许重复", existing_id: existing.id }, status: :conflict
        end

        # 创建发文数据
        post_stat = PostStat.new(
          account_id: account.id,
          post_date: params[:post_date],
          title: params[:title],
          url: params[:url],
          likes_count: params[:likes_count] || 0,
          shares_count: params[:shares_count] || 0,
          comments_count: params[:comments_count] || 0,
          views_count: params[:views_count] || 0,
          data_updated_at: params[:data_updated_at].present? ? Time.parse(params[:data_updated_at]) : Time.current
        )

        if post_stat.save
          render json: {
            code: 200,
            msg: '发文数据保存成功',
            data: {
              id: post_stat.id,
              account_id: account.id,
              post_date: post_stat.post_date,
              title: post_stat.title,
              url: post_stat.url,
              likes_count: post_stat.likes_count,
              shares_count: post_stat.shares_count,
              comments_count: post_stat.comments_count,
              views_count: post_stat.views_count
            }
          }
        else
          render json: { code: 500, msg: "保存失败: #{post_stat.errors.full_messages.join(', ')}" }, status: :internal_server_error
        end
      rescue ActiveRecord::RecordInvalid => e
        render json: { code: 400, msg: "数据无效: #{e.message}" }, status: :bad_request
      rescue => e
        render json: { code: 500, msg: "服务器错误: #{e.message}" }, status: :internal_server_error
      end

      # POST /api/v1/post_stats/batch
      # 批量接收发文数据
      # 请求参数:
      # {
      #   stats: [
      #     { account_id: 1, post_date: "...", url: "...", ... },
      #     { account_id: 2, post_date: "...", url: "...", ... }
      #   ]
      # }
      def batch_create
        stats = params[:stats]
        if stats.blank? || !stats.is_a?(Array)
          return render json: { code: 400, msg: 'stats 参数必须是数组' }, status: :bad_request
        end

        results = []
        errors = []

        stats.each_with_index do |stat_params, index|
          # 检查 url 是否已存在
          if stat_params[:url].blank?
            errors << { index: index, error: "url 不能为空" }
            next
          end

          existing = PostStat.find_by(url: stat_params[:url])
          if existing
            errors << { index: index, url: stat_params[:url], error: "url 已存在" }
            next
          end

          account = Account.find_by(id: stat_params[:account_id])
          if account.blank?
            errors << { index: index, account_id: stat_params[:account_id], error: "账号不存在" }
            next
          end

          post_stat = PostStat.new(
            account_id: account.id,
            post_date: stat_params[:post_date],
            title: stat_params[:title],
            url: stat_params[:url],
            likes_count: stat_params[:likes_count] || 0,
            shares_count: stat_params[:shares_count] || 0,
            comments_count: stat_params[:comments_count] || 0,
            views_count: stat_params[:views_count] || 0,
            data_updated_at: stat_params[:data_updated_at].present? ? Time.parse(stat_params[:data_updated_at]) : Time.current
          )

          if post_stat.save
            results << { index: index, success: true, id: post_stat.id }
          else
            errors << { index: index, url: stat_params[:url], error: post_stat.errors.full_messages.join(', ') }
          end
        end

        render json: {
          code: 200,
          msg: "处理完成",
          data: {
            success_count: results.length,
            error_count: errors.length,
            results: results,
            errors: errors
          }
        }
      end
    end
  end
end