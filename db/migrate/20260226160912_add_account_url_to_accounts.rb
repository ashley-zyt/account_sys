class AddAccountUrlToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :source_url, :string, comment:"账号主页链接"
    add_index :accounts, :source_url
  end
end