class OperationLog < ApplicationRecord
  def self.ransackable_attributes(auth_object = nil)
    %w[admin_id admin_name action controller action_name target_type target_id description ip_address created_at]
  end

  def action_label
    {
      'create' => '新增',
      'update' => '编辑',
      'destroy' => '删除',
      'index' => '查看列表',
      'show' => '查看详情',
      'new' => '新建页面',
      'edit' => '编辑页面'
    }[action] || action
  end

  def target_label
    return '-' unless target_type.present? && target_id.present?
    "#{target_type}##{target_id}"
  end
end
