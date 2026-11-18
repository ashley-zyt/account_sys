class CreateDirectPublishLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :direct_publish_logs do |t|
      t.bigint   :account_id
      t.string   :platform
      t.integer  :media_type,    null: false, default: 1   # video/image/text
      t.string   :publish_channel                            # x_api/postforme/postpeer
      t.text     :text
      t.string   :title
      t.text     :description
      t.text     :media_urls                                 # JSON 数组
      t.integer  :status,        null: false, default: 0    # pending/success/failed
      t.text     :error_msg
      t.string   :external_id                                # post_id/tweet_id/media_id
      t.string   :task_uuid                                  # X 视频异步发推回写用（create_task_log）
      t.datetime :actual_publish_time                        # 发推成功时间（XPostPoller 回写）
      t.timestamps
    end
    add_index :direct_publish_logs, :account_id
    add_index :direct_publish_logs, :platform
    add_index :direct_publish_logs, :publish_channel
    add_index :direct_publish_logs, :status
    add_index :direct_publish_logs, :task_uuid, unique: true
  end
end
