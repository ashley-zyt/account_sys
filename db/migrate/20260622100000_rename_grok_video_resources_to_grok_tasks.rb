class RenameGrokVideoResourcesToGrokTasks < ActiveRecord::Migration[6.1]
  def change
    rename_table :grok_video_resources, :grok_tasks
    # rename_table 会自动重命名所有 index_grok_video_resources_* 索引为 index_grok_tasks_*，无需手动处理
  end
end
