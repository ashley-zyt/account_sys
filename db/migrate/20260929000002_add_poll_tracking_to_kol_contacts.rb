# KOL 联系方式加回复轮询追踪字段
class AddPollTrackingToKolContacts < ActiveRecord::Migration[6.1]
  def change
    add_column :kol_contacts, :last_sent_at, :datetime,
               comment: '最后发送成功时间（回复轮询频率衰减的基准）'
    add_column :kol_contacts, :next_poll_at, :datetime,
               comment: '下次回复轮询时间（按发送成功后衰减频率计算）'
    add_index :kol_contacts, :next_poll_at
  end
end
