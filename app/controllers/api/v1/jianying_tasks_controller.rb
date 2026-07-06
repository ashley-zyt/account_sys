module Api
  module V1
    class JianyingTasksController < BaseController

      # POST /api/v1/jianying_tasks/batch
      # body: {
      #   tasks: [
      #     {
      #       keyword: "#北海#涠洲岛海景竖图素材",
      #       keyword_code: "A0001",
      #       theme: "中国美食制作",
      #       associated_images: ["jinshu.jpg","shuijin.jpg"],
      #       oss_key: "S_food/12345.mp4"
      #     },
      #     ...
      #   ]
      # }
      def batch
        tasks = params[:tasks]
        unless tasks.is_a?(Array) && tasks.any?
          return render_error(msg: "tasks 不能为空，需传递数组")
        end

        accepted = 0
        errors   = []

        tasks.each_with_index do |item, idx|
          keyword       = item[:keyword].to_s.strip
          keyword_code  = item[:keyword_code].to_s.strip
          theme         = item[:theme].to_s.strip
          images        = item[:associated_images]
          oss_key       = item[:oss_key].to_s.strip

          if keyword.blank? || keyword_code.blank? || theme.blank? || oss_key.blank?
            errors << { index: idx, error: "keyword/keyword_code/theme/oss_key 不能为空" }
            next
          end

          created = JianyingTask.batch_create_from_api([{
            keyword: keyword, keyword_code: keyword_code, theme: theme,
            associated_images: images, oss_key: oss_key
          }])
          accepted += created
        rescue => e
          Rails.logger.error "[JianyingApi] 创建任务失败 (index=#{idx}): #{e.message}"
          errors << { index: idx, error: e.message }
        end

        render_success(
          msg: "批量接收完成",
          data: { accepted: accepted, errors: errors }
        )
      end
    end
  end
end
