class AddKolSleepUntilToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :kol_sleep_until, :datetime, comment: "KOL触达休眠截止时间（内部账号风控后暂停调度）"
    add_index :accounts, :kol_sleep_until
  end
end
