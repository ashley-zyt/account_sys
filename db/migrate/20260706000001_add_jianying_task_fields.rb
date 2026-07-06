class AddJianyingTaskFields < ActiveRecord::Migration[6.1]
  def change
    add_column :jianying_tasks, :keyword, :string, comment: "关键词" unless column_exists?(:jianying_tasks, :keyword)
    add_column :jianying_tasks, :keyword_code, :string, comment: "关键词编码" unless column_exists?(:jianying_tasks, :keyword_code)
    add_column :jianying_tasks, :associated_images, :text, comment: "关联图片（JSON数组）" unless column_exists?(:jianying_tasks, :associated_images)

    add_index :jianying_tasks, :keyword_code unless index_exists?(:jianying_tasks, :keyword_code)
  end
end
