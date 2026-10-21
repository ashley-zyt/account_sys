# 凭证表支持「客户托管账号」凭证：加 hosting_account_id，account_id 改为可空。
# 二者互斥区分自有/托管：account_id 非空=自有账号，hosting_account_id 非空=托管账号。
class AddHostingAccountToCredentials < ActiveRecord::Migration[6.1]
  def change
    add_reference :x_account_credentials, :hosting_account, foreign_key: true, null: true, index: { unique: true }
    change_column_null :x_account_credentials, :account_id, true

    add_reference :postpeer_accounts, :hosting_account, foreign_key: true, null: true, index: { unique: true }
    change_column_null :postpeer_accounts, :account_id, true

    add_reference :postforme_accounts, :hosting_account, foreign_key: true, null: true, index: { unique: true }
    change_column_null :postforme_accounts, :account_id, true
  end
end
