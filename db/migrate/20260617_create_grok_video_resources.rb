class CreateGrokVideoResources < ActiveRecord::Migration[6.1]
  def change
    create_table :grok_video_resources do |t|
      t.string :theme
      t.string :video_url
      t.integer :status, default: 0
      t.text :prompt
      t.bigint :grok_image_id
      t.bigint :account_id
      t.text :error_msg
      t.datetime :start_at
      t.datetime :actual_publish_time
      t.bigint :browser_id
      t.string :task_uuid
      t.integer :platform
      t.text :title
      t.text :description

      t.timestamps
    end
    add_index :grok_video_resources, :theme
    add_index :grok_video_resources, :status
    add_index :grok_video_resources, :task_uuid, unique: true
    add_index :grok_video_resources, :account_id
    add_index :grok_video_resources, :browser_id
    add_index :grok_video_resources, :grok_image_id
  end
end