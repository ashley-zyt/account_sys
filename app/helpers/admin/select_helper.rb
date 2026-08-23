# 视图辅助：渲染可搜索下拉（单选）。自动根据 selected 反查显示标签。
module Admin::SelectHelper
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
