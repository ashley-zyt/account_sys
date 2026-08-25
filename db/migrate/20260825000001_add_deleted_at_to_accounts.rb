class AddDeletedAtToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :deleted_at, :datetime, comment: "软删除时间（非空表示已删除，进回收站）"
    add_index :accounts, :deleted_at
  end
end
