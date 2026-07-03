# == Schema Information
#
# Table name: operation_logs
#
#  id                                          :bigint           not null, primary key
#  action(操作类型（create/update/destroy等）) :string(255)
#  action_name(动作名称)                       :string(255)
#  admin_name(操作用户名（冗余存储）)          :string(255)
#  controller(控制器名称)                      :string(255)
#  description(操作描述)                       :text(65535)
#  ip_address(操作IP地址)                      :string(255)
#  params(请求参数（JSON格式）)                :text(65535)
#  target_type(目标模型类型)                   :string(255)
#  created_at                                  :datetime         not null
#  updated_at                                  :datetime         not null
#  admin_id(操作用户ID)                        :integer
#  target_id(目标模型ID)                       :integer
#
# Indexes
#
#  index_operation_logs_on_admin_id                   (admin_id)
#  index_operation_logs_on_created_at                 (created_at)
#  index_operation_logs_on_target_type_and_target_id  (target_type,target_id)
#
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
