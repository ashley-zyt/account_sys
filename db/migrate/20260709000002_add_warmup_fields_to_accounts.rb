class AddWarmupFieldsToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :last_warmup_at, :datetime
    add_column :accounts, :warmup_enabled, :boolean, default: true
    add_column :accounts, :warmup_frequency, :string, default: 'weekly'
    add_column :accounts, :warmup_status, :string
    add_column :accounts, :warmup_batch, :integer, default: 0
    add_column :accounts, :machine, :string
  end
end