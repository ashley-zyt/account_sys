class CreateNotebooklmTasks < ActiveRecord::Migration[6.1]
  def change
    create_table :notebooklm_tasks do |t|
      t.string  :task_uuid, comment: "任务唯一标识，用于关联日志"

      # 视频与账号信息
      t.text    :oss_url,      comment: "NotebookLM视频OSS签名地址"
      t.text    :full_oss_url, comment: "完整OSS视频object key"
      t.bigint  :account_id,   comment: "发布账号ID"

      t.string  :theme,        comment: "内容主题"
      t.string  :keyword,      comment: "关键词"
      t.string  :title,        limit: 280, comment: "发布标题"
      t.string  :description,  limit: 280, comment: "视频描述"

      # 任务状态
      t.integer :status, default: 0, comment: "任务状态 pending/waiting_publish/executing/success/failed"
      t.text    :error_msg, comment: "错误信息/失败原因"

      # 时间信息
      t.datetime :start_at,            comment: "任务开始时间"
      t.datetime :actual_publish_time, comment: "实际发布时间"

      # 执行环境
      t.bigint  :browser_id, comment: "执行任务的浏览器ID"
      t.integer :platform,   comment: "目标发布平台"
      t.string  :group_id,   comment: "任务组ID"
      # 关联的NotebookLM关键词ID，便于追溯来源
      t.bigint  :notebooklm_keyword_id, comment: "来源NotebookLM关键词ID"

      t.timestamps
    end

    add_index :notebooklm_tasks, :task_uuid, unique: true
    add_index :notebooklm_tasks, :browser_id
    add_index :notebooklm_tasks, :account_id
    add_index :notebooklm_tasks, :status
    add_index :notebooklm_tasks, :platform
    add_index :notebooklm_tasks, :group_id
    add_index :notebooklm_tasks, :theme
    add_index :notebooklm_tasks, :notebooklm_keyword_id
  end
end