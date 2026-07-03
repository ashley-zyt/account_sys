class CreateOperationLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :operation_logs do |t|
      t.integer :admin_id, comment: '操作用户ID'
      t.string :admin_name, comment: '操作用户名（冗余存储）'
      t.string :action, comment: '操作类型（create/update/destroy等）'
      t.string :controller, comment: '控制器名称'
      t.string :action_name, comment: '动作名称'
      t.string :target_type, comment: '目标模型类型'
      t.integer :target_id, comment: '目标模型ID'
      t.text :description, comment: '操作描述'
      t.string :ip_address, comment: '操作IP地址'
      t.text :params, comment: '请求参数（JSON格式）'

      t.timestamps
    end

    add_index :operation_logs, :admin_id
    add_index :operation_logs, [:target_type, :target_id]
    add_index :operation_logs, :created_at
  end
end
