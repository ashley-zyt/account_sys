class AddPushedToHuashengKeywords < ActiveRecord::Migration[6.1]
  def change
    add_column :huasheng_keywords, :pushed, :boolean, default: false, null: false, comment: "是否已推送到花生资源队列"
    add_index :huasheng_keywords, :pushed unless index_exists?(:huasheng_keywords, :pushed)
  end
end
