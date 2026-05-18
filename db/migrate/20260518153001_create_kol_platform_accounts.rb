class CreateKolPlatformAccounts < ActiveRecord::Migration[7.2]
  def change
    create_table :kol_platform_accounts do |t|
      t.references :kol, null: false, foreign_key: true

      t.integer :platform, null: false, comment: "平台"

      t.string :nick_name, null: false, comment: "平台昵称"

      t.string :profile_url, comment: "主页链接"

      t.string :follower_count, comment: "粉丝数"

      t.timestamps
    end

    add_index :kol_platform_accounts, :platform
    add_index :kol_platform_accounts, :nick_name
  end
end