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

      private

      def parse_image_names(kw)
        JSON.parse(kw.image_names) rescue []
      end
    end
  end
end
