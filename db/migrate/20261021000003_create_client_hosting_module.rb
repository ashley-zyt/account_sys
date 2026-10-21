# 客户托管模块：客户 + 托管账号 + 托管发布任务（独立于自有账号体系）
class CreateClientHostingModule < ActiveRecord::Migration[6.1]
  def change
    create_table :clients do |t|
      t.string :name, null: false, comment: '客户名称'
      t.string :contact, comment: '联系人'
      t.string :contact_info, comment: '联系方式'
      t.integer :status, null: false, default: 0, comment: '状态 0合作中 1暂停 2终止'
      t.text :remark, comment: '备注'
      t.timestamps
    end
    add_index :clients, :name, unique: true

    create_table :hosting_accounts do |t|
      t.references :client, null: false, foreign_key: true, comment: '归属客户'
      t.string :platform, null: false, comment: '平台（twitter/youtube/tiktok/instagram/facebook）'
      t.string :theme, comment: '主题（用于资源分配匹配）'
      t.string :resource_queue, comment: '资源队列（WorkMode key，如 move/jianying）'
      t.string :publish_channel, comment: '发布渠道（postpeer/postforme/x）'
      t.integer :status, null: false, default: 0, comment: '状态 0托管中 1暂停 2终止'
      t.text :remark, comment: '备注'
      t.timestamps
    end
    add_index :hosting_accounts, :platform
    add_index :hosting_accounts, :theme

    create_table :hosting_publish_tasks do |t|
      t.string :resource_type, comment: '资源队列成品多态类型（如 MoveTask）'
      t.bigint :resource_id, comment: '资源队列成品多态 ID'
      t.string :platform, comment: '目标平台'
      t.string :theme, comment: '主题'
      t.references :hosting_account, null: false, foreign_key: true, comment: '托管账号'
      t.references :client, null: false, foreign_key: true, comment: '归属客户'
      t.string :publish_channel, comment: '发布渠道'
      t.integer :status, null: false, default: 0, comment: '状态 0待发布 1执行中 2成功 3失败'
      t.text :error_msg, comment: '失败原因'
      t.datetime :executed_at, comment: '执行时间'
      t.timestamps
    end
    add_index :hosting_publish_tasks, [:resource_type, :resource_id]
    add_index :hosting_publish_tasks, :status
  end
end
