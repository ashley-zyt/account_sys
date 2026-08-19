class CreateKols < ActiveRecord::Migration[6.1]
  def change
    create_table :kols do |t|
      t.string :name, null: false, comment: "KOL名称/常用用户名"
      t.string :category, comment: "所属领域"
      t.string :follower_tier, comment: "粉丝量级"
      t.string :country, comment: "所在国家/地区"
      t.string :language, null: false, comment: "使用语言（必填）"
      t.string :owner, null: false, comment: "归属人（负责人）"
      t.text :notes, comment: "备注"

      # 第一层：KOL 业务生命周期状态
      # reserved / pending / contacting / replied_unprocessed /
      # negotiating / cooperating / failed / unresponsive
      t.integer :status, null: false, default: 0, comment: "KOL业务生命周期状态"

      t.bigint :current_contact_id, comment: "当前正在触达的联系方式ID"
      t.bigint :current_account_id, comment: "当前分配的内部账号ID"
      t.datetime :next_action_at, comment: "下次可执行自动化动作的时间（等待期结束）"
      t.datetime :last_contacted_at, comment: "最后一次触达时间"

      t.timestamps
    end

    add_index :kols, :name
    add_index :kols, :category
    add_index :kols, :owner
    add_index :kols, :status
    add_index :kols, :language
    add_index :kols, :next_action_at
  end
end
