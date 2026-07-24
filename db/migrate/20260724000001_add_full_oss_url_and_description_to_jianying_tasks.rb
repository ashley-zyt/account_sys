class AddFullOssUrlAndDescriptionToJianyingTasks < ActiveRecord::Migration[6.1]
  def change
    add_column :jianying_tasks, :full_oss_url, :string, comment: "完整OSS视频地址" unless column_exists?(:jianying_tasks, :full_oss_url)
    add_column :jianying_tasks, :description, :string, comment: "视频描述" unless column_exists?(:jianying_tasks, :description)
  end
end