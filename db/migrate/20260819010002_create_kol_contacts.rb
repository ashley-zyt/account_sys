class CreateKolContacts < ActiveRecord::Migration[6.1]
  def change
    create_table :kol_contacts do |t|
      t.references :kol, type: :bigint, null: false, foreign_key: true

      # 平台/渠道：facebook/twitter/tiktok/youtube/instagram/email/telegram/whatsapp
      t.integer :platform, null: false, comment: "平台或通讯渠道"
      t.string :nickname, comment: "平台昵称/账号"
      t.string :url, comment: "主页链接或联系方式"

      # 触达优先级：数值越小越优先
      t.integer :priority, null: false, default: 0, comment: "触达优先级（越小越优先）"
      t.boolean :messaging_enabled, null: false, default: false, comment: "是否可作为发信渠道"
      t.integer :status, null: false, default: 0, comment: "联系方式状态：active/disabled"
      t.datetime :last_used_at, comment: "最后使用时间"

      t.timestamps
    end unless table_exists?(:kol_contacts)

    add_index :kol_contacts, :platform unless index_exists?(:kol_contacts, :platform)
    add_index :kol_contacts, :priority unless index_exists?(:kol_contacts, :priority)
    add_index :kol_contacts, :status unless index_exists?(:kol_contacts, :status)
  end
end
