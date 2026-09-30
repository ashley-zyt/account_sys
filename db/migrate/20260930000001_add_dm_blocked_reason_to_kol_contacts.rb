class AddDmBlockedReasonToKolContacts < ActiveRecord::Migration[6.1]
  def change
    add_column :kol_contacts, :dm_blocked_reason, :integer,
               comment: '对方不可私信原因（人工标记）0=仅关注者可私信 1=需要验证账号 2=关闭私信 3=账号被暂停 4=@username失效'
  end
end
