module Admin
  # 视图辅助：渲染可搜索下拉（单选）。自动根据 selected 反查显示标签。
  module SelectHelper
    def admin_searchable_select(name, options, selected: nil, placeholder: "请选择", include_blank: nil, required: false)
      selected_str = selected.nil? ? "" : selected.to_s
      selected_label = nil
      unless selected_str.empty?
        pair = options.find { |label, value| value.to_s == selected_str }
        selected_label = pair ? pair[0].to_s : nil
      end

      render "admin/shared/searchable_select",
        name: name,
        options: options,
        selected: selected,
        selected_label: selected_label,
        placeholder: placeholder,
        include_blank: include_blank,
        required: required
    end
  end

  # 表单构建器扩展：将 f.select 平滑替换为 f.searchable_select。
  # 签名与 f.select 一致：searchable_select(method, choices, options = {}, html_options = {})
  module SearchableSelectFormBuilder
    def searchable_select(method, choices = nil, options = {}, html_options = {}, &block)
      opts = options || {}
      html = html_options || {}

      name = "#{object_name}[#{method}]"

      # Ransack 搜索表单（object_name == "q"）从 params[:q] 取当前值；普通表单从对象取
      selected =
        if object_name.to_s == "q"
          @template.params.dig(:q, method)
        else
          object.respond_to?(method) ? object.public_send(method) : nil
        end

      placeholder = opts[:placeholder] || opts[:include_blank] || "请选择"
      include_blank = opts.key?(:include_blank) ? opts[:include_blank] : nil

      @template.admin_searchable_select(
        name,
        choices || [],
        selected: selected,
        placeholder: placeholder,
        include_blank: include_blank,
        required: html[:required]
      )
    end
  end
end
