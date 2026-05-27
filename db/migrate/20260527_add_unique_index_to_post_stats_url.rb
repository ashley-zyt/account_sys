class AddUniqueIndexToPostStatsUrl < ActiveRecord::Migration[6.1]
  def change
    add_index :post_stats, :url, unique: true
  end
end