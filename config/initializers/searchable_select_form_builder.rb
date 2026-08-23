# 让所有表单（含 Ransack search_form_for）支持 f.searchable_select
Rails.application.config.after_initialize do
  ActionView::Helpers::FormBuilder.prepend(Admin::SearchableSelectFormBuilder)
end
