# 表单构建器扩展：让所有表单（含 Ransack search_form_for）支持 f.searchable_select。
# 注意：不要用 Admin:: 命名空间（app/models/admin.rb 中 Admin 是 class，会触发 "not a module"）。
module SearchableSelectFormBuilder
  # 签名与 f.select 一致：searchable_select(method, choices, options = {}, html_options = {})
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

# 普通表单（form_with）：ActionView 加载完成后挂载
ActiveSupport.on_load(:action_view) do
  ActionView::Helpers::FormBuilder.prepend(SearchableSelectFormBuilder)
end

# Ransack 搜索表单（search_form_for）：每次请求前确保已挂载（开发模式下代码会重载）
Rails.application.config.to_prepare do
  if defined?(Ransack::Helpers::FormBuilder)
    Ransack::Helpers::FormBuilder.prepend(SearchableSelectFormBuilder)
  end
end
