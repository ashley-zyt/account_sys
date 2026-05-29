class AddOperatorToAccounts < ActiveRecord::Migration[7.0]
  def change
    add_column :accounts, :operator, :string
  end
end