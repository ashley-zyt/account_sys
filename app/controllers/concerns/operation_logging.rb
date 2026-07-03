module OperationLogging
  extend ActiveSupport::Concern

  included do
    after_action :log_operation, only: [:create, :update, :destroy]
  end

  def log_operation
    return unless current_admin

    resource = instance_variable_get("@#{controller_name.singularize}")
    target_type = resource&.class&.name
    target_id = resource&.id

    description = build_description(action_name, target_type, target_id, resource)

    OperationLog.create!(
      admin_id: current_admin.id,
      admin_name: current_admin.email,
      action: action_name,
      controller: controller_name,
      action_name: action_name,
      target_type: target_type,
      target_id: target_id,
      description: description,
      ip_address: request.remote_ip,
      params: filtered_params
    )
  rescue => e
    Rails.logger.error "[OperationLogging] 记录操作日志失败: #{e.message}"
  end

  private

  def build_description(action, target_type, target_id, resource)
    case action
    when 'create'
      "新增了 #{target_type}##{target_id}"
    when 'update'
      "编辑了 #{target_type}##{target_id}"
    when 'destroy'
      "删除了 #{target_type}##{target_id}"
    else
      "#{action} #{target_type}##{target_id}"
    end
  end

  def filtered_params
    params.to_unsafe_h.except(:controller, :action, :format, :authenticity_token).to_json rescue '{}'
  end
end
