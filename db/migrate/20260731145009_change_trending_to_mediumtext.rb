class ChangeTrendingToMediumtext < ActiveRecord::Migration[6.0+]
  def up
    # 直接用 SQL 修改
    execute "ALTER TABLE crypto_videos MODIFY trending MEDIUMTEXT"
  end
end