module Api
  module V1
    class HuashengController < BaseController

      # GET /api/v1/huasheng/pending_keywords
      # 批量获取状态为"未启动"(status=0)的关键词
      # params:
      #   limit  - 可选，每次获取条数，默认 10，最大 50
      #   theme  - 可选，按主题过滤
      def pending_keywords
        limit = (params[:limit] || 10).to_i.clamp(1, 50)
        scope = HuashengKeyword.where(status: 0)
        scope = scope.where(theme: params[:theme]) if params[:theme].present?
        keywords = scope.order(:id).limit(limit)

        result = keywords.map do |kw|
          {
            id:         kw.id,
            theme:      kw.theme,
            keyword:    kw.keyword,
            status:     kw.status,
            status_name: kw.status_name,
            created_at: kw.created_at&.strftime("%Y-%m-%d %H:%M:%S")
          }
        end

        render_success(
          data: { total: result.size, keywords: result },
          msg: "查询成功"
        )
      end

      # POST /api/v1/huasheng/update_status
      # 批量修改关键词状态
      # body: { ids: [1, 2, 3], status: 1 }
      # status: 0未启动 1待执行 2执行中 3执行完成 4任务失败
      def update_status
        ids    = params[:ids]
        status = params[:status].to_i

        unless ids.is_a?(Array) && ids.any?
          return render_error(msg: "ids 不能为空，需传递整数数组")
        end

        unless HuashengKeyword::STATUS_NAMES.key?(status)
          return render_error(msg: "status 无效，可选值：#{HuashengKeyword::STATUS_NAMES.map { |k, v| "#{k}=#{v}" }.join(', ')}")
        end

        keywords = HuashengKeyword.where(id: ids)
        updated  = 0
        failed   = []

        keywords.each do |kw|
          if kw.update(status: status)
            updated += 1
          else
            failed << { id: kw.id, error: kw.errors.full_messages.join(", ") }
          end
        end

        not_found = ids.map(&:to_i) - keywords.pluck(:id)

        render_success(
          data: {
            updated:   updated,
            failed:    failed,
            not_found: not_found
          },
          msg: "更新完成"
        )
      end

      # POST /api/v1/huasheng/report_result
      # 传递任务结果，并修改任务状态为执行完成或任务失败
      # body: { id: 1, status: 3, result_data: {...}, task_id: "xxx" }
      # status: 3执行完成 4任务失败
      def report_result
        id     = params[:id]
        status = params[:status].to_i

        unless id.present?
          return render_error(msg: "id 不能为空")
        end

        unless [3, 4].include?(status)
          return render_error(msg: "status 无效，仅支持 3=执行完成 或 4=任务失败")
        end

        kw = HuashengKeyword.find_by(id: id)
        return render_error(msg: "关键词不存在: id=#{id}", status: :not_found) unless kw

        update_attrs = { status: status }
        update_attrs[:task_id]     = params[:task_id]     if params[:task_id].present?
        update_attrs[:result_data] = params[:result_data].is_a?(String) ? params[:result_data] : params[:result_data].to_json if params[:result_data].present?

        if kw.update(update_attrs)
          render_success(
            data: {
              id:          kw.id,
              theme:       kw.theme,
              keyword:     kw.keyword,
              status:      kw.status,
              status_name: kw.status_name,
              task_id:      kw.task_id,
              updated_at:  kw.updated_at&.strftime("%Y-%m-%d %H:%M:%S")
            },
            msg: status == 3 ? "任务已标记为执行完成" : "任务已标记为失败"
          )
        else
          render_error(msg: "更新失败：#{kw.errors.full_messages.join(', ')}")
        end
      end
    end
  end
end
