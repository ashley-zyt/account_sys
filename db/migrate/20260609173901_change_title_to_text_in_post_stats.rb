class ChangeTitleToTextInPostStats < ActiveRecord::Migration[6.1]
  def change
    change_column :post_stats, :title, :text
  end
end