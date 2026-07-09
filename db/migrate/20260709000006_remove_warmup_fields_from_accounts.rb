class RemoveWarmupFieldsFromAccounts < ActiveRecord::Migration[7.0]
  def change
    remove_column :accounts, :last_warmup_at, :datetime
    remove_column :accounts, :warmup_enabled, :boolean
    remove_column :accounts, :warmup_frequency, :string
    remove_column :accounts, :warmup_status, :string
    remove_column :accounts, :warmup_batch, :integer
    remove_column :accounts, :machine, :string
  end
end