class AddUsernameAndHomepageUrlToHostingAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :hosting_accounts, :username, :string, comment: '账号用户名'
    add_column :hosting_accounts, :homepage_url, :string, comment: '账号主页链接'
  end
end
