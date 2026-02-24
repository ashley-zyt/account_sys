class CreateAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :accounts do |t|
      t.integer :platform,    default: 1,comment: '平台：facebook/twitter/tiktok/youtube/instagram'
      t.string :account_name, comment: '账号名'
      t.integer :status,      default: 0, comment: '账号状态'
      t.string :theme,        comment: '账号主题'
      t.integer :work_type,   comment: '工作运行方式：搬运/coze/其他'

      t.bigint :browser_id,   comment: '绑定的指纹浏览器ID'

      t.string :remark, comment: '备注信息'

      t.timestamps
    end

    add_index :accounts, :browser_id
    add_index :accounts, :platform
  end
end
