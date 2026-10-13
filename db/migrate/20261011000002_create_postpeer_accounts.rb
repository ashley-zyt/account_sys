class CreatePostpeerAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :postpeer_accounts do |t|
      t.bigint :account_id, null: false, comment: "本系统账号 ID（一对一）"
      t.string :profile_id, comment: "postpeer profile ID（授权时隔离账号，用于反查 accountId）"
      t.string :peer_account_id, comment: "postpeer 集成 ID（accountId，发布时用）"
      t.integer :auth_status, null: false, default: 0, comment: "授权状态 0未授权 1授权中 2已授权 3失败"
      t.datetime :authorized_at, comment: "授权完成时间"
      t.timestamps
    end

    add_index :postpeer_accounts, :account_id, unique: true
    add_index :postpeer_accounts, :peer_account_id
  end
end
