# KOL 联系方式加 X API 触达相关字段
class AddXOutreachToKolContacts < ActiveRecord::Migration[6.1]
  def change
    add_column :kol_contacts, :outreach_channel, :integer, default: 1, null: false,
               comment: '触达方式 0=指纹浏览器 1=X认证（默认 X认证）'
    add_column :kol_contacts, :x_user_id, :string, comment: 'X平台 user id 缓存（@username 解析后缓存）'
    add_index :kol_contacts, :x_user_id
  end
end
