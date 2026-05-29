class AddOperatorToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :operator, :string
  end
end