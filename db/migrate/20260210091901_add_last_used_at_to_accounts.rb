class AddLastUsedAtToAccounts < ActiveRecord::Migration[5.2]
  def change
    add_column :accounts, :last_used_at, :datetime, comment:"最后一次使用时间"
    add_index :accounts, :last_used_at
  end
end