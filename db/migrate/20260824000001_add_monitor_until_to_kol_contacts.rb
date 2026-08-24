class AddMonitorUntilToKolContacts < ActiveRecord::Migration[6.1]
  def change
    add_column :kol_contacts, :monitor_until, :datetime, comment: "回复监测截止时间（该联系方式最后一次发送成功时间 + 30 天）"
    add_index :kol_contacts, :monitor_until
  end
end
