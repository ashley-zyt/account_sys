class RenameSocialAccountIdToAccountId < ActiveRecord::Migration[6.1]
  def change
    rename_column :conversations, :social_account_id, :account_id
  end
end