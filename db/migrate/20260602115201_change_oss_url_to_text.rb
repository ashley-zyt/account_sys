class ChangeOssUrlToTextInOperationTasks < ActiveRecord::Migration[6.1]
  def change
    change_column :operation_tasks, :oss_url, :text
  end
end