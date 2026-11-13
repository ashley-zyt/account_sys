class CreateExternalResourcesAndPublishTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :external_resources do |t|
      t.string   :theme,       null: false
      t.integer  :source,      null: false, default: 0   # 来源：grok_bot 等
      t.integer  :media_type,  null: false, default: 1   # 媒体形态：video/image/text
      t.text     :text                             # 文字内容（可空）
      t.text     :media_urls                        # JSON 数组：图片多张/视频1个
      t.text     :platforms                         # JSON 数组：目标平台
      t.integer  :status,      null: false, default: 0   # pending/queued/published/failed
      t.timestamps
    end
    add_index :external_resources, :theme
    add_index :external_resources, :status
    add_index :external_resources, :source

    create_table :external_publish_tasks do |t|
      t.string   :theme
      t.integer  :platform                               # 目标平台
      t.integer  :media_type,  null: false, default: 1   # video/image/text
      t.text     :text                             # 文字内容
      t.text     :media_urls                        # JSON 数组
      t.string   :title
      t.integer  :status,      null: false, default: 0
      t.bigint   :account_id
      t.bigint   :browser_id
      t.integer  :failure_count, null: false, default: 0
      t.string   :task_uuid
      t.text     :error_msg
      t.datetime :start_at
      t.datetime :actual_publish_time
      t.bigint   :external_resource_id
      t.timestamps
    end
    add_index :external_publish_tasks, :task_uuid, unique: true
    add_index :external_publish_tasks, :status
    add_index :external_publish_tasks, :account_id
    add_index :external_publish_tasks, :theme
    add_index :external_publish_tasks, :platform
    add_index :external_publish_tasks, :external_resource_id
  end
end
