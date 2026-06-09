class ChangeUrlToTextInPostStats < ActiveRecord::Migration[6.1]
  def change
    change_column :post_stats, :url, :text
  end
end