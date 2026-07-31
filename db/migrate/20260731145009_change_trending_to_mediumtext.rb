class ChangeTrendingToMediumtext < ActiveRecord::Migration[6.1]
  def change
    # 直接用 SQL 修改
    change_column :crypto_videos, :trending, :text, limit: 16_777_215
  end
end