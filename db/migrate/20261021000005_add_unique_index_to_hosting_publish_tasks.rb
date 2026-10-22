# 托管发布任务：一个成品（resource_type + resource_id）只允许一条托管发布任务，避免重复发。
class AddUniqueIndexToHostingPublishTasks < ActiveRecord::Migration[6.1]
  def change
    # 之前的普通索引改为唯一索引
    remove_index :hosting_publish_tasks, column: [:resource_type, :resource_id]
    add_index :hosting_publish_tasks, [:resource_type, :resource_id], unique: true
  end
end
