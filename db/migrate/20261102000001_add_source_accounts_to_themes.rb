class AddSourceAccountsToThemes < ActiveRecord::Migration[6.1]
  def change
    add_column :themes, :source_accounts, :text, comment: '搬运对标账号主页链接（每行一个）'
  end
end
