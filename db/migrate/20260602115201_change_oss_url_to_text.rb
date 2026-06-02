class ChangeOssUrlToTextInOperationTasks < ActiveRecord::Migration[7.0]
  def change
    change_column :operation_tasks, :oss_url, :text
  end
end