module Api
  module V1
    class RedNoteController < BaseController

      # POST /api/v1/red_note/keywords
      # body: { keyword_codes: ["A0001", "A0002"] }
      def keywords
        codes = params[:keyword_codes]
        unless codes.is_a?(Array) && codes.any?
          return render_error(msg: "keyword_codes 不能为空，需传递字符串数组")
        end

        keywords = RedNoteKeyword.where(keyword_code: codes).order(:keyword_code)

        result = keywords.map do |kw|
          image_names = parse_image_names(kw)
          {
            id: kw.id,
            theme: kw.theme,
            keyword: kw.keyword,
            keyword_code: kw.keyword_code,
            status: kw.status,
            status_name: kw.status_name,
            task_id: kw.task_id,
            image_names: image_names,
            image_count: image_names.size,
            created_at: kw.created_at&.strftime("%Y-%m-%d %H:%M:%S"),
            updated_at: kw.updated_at&.strftime("%Y-%m-%d %H:%M:%S")
          }
        end

        render_success(
          data: { total: result.size, keywords: result },
          msg: "查询成功"
        )
      end

      # POST /api/v1/red_note/batch_add_keywords
      # body: {
      #   theme: "剪映-美食",
      #   keywords: [
      #     { keyword: "#北海#涠洲岛海景竖图素材", keyword_code: "A0002" },
      #     { keyword: "桂林山水风景图片", keyword_code: "B0003" }
      #   ]
      # }
      def batch_add_keywords
        theme = params[:theme].to_s.strip
        keywords = params[:keywords]

        return render_error(msg: "theme 不能为空") if theme.blank?
        return render_error(msg: "keywords 不能为空，需传递数组") unless keywords.is_a?(Array) && keywords.any?

        # 去掉"剪映-"前缀，与 admin 端创建逻辑一致
        theme = theme.gsub("剪映-", "")

        existing_codes = RedNoteKeyword.pluck(:keyword_code)
        created = []
        failed = []

        keywords.each do |item|
          kw = item["keyword"].to_s.strip
          code = item["keyword_code"].to_s.strip

          if kw.blank? || code.blank?
            failed << { keyword: kw, keyword_code: code, error: "keyword 或 keyword_code 为空" }
            next
          end

          if existing_codes.include?(code)
            failed << { keyword: kw, keyword_code: code, error: "编码 #{code} 已存在" }
            next
          end

          record = RedNoteKeyword.new(theme: theme, keyword: kw, keyword_code: code)
          if record.save
            created << { keyword: kw, keyword_code: code }
            existing_codes << code
          else
            failed << { keyword: kw, keyword_code: code, error: record.errors.full_messages.join(", ") }
          end
        end

        render_success(
          data: {
            total: keywords.size,
            created: created.size,
            failed: failed.size,
            created_list: created,
            failed_list: failed
          },
          msg: "批量添加完成：成功 #{created.size} 个，失败 #{failed.size} 个"
        )
      rescue => e
        Rails.logger.error "[RedNote API] 批量添加关键词失败: #{e.message}"
        render_error(msg: "批量添加失败: #{e.message}")
      end

      private

      def parse_image_names(kw)
        JSON.parse(kw.image_names) rescue []
      end
    end
  end
end
