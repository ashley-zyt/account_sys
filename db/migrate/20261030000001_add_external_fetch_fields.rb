# 外部采集系统字段：
# - accounts.external_fetch_enabled：是否走外部采集系统（开关）
# - accounts.external_user_id / hosting_accounts.external_user_id：采集系统的账号标识
class AddExternalFetchFields < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :external_fetch_enabled, :boolean, default: false, null: false, comment: '是否走外部采集系统'
    add_column :accounts, :external_user_id, :string, comment: '外部采集系统的账号标识（各平台 user_id 或 username）'
    add_column :hosting_accounts, :external_user_id, :string, comment: '外部采集系统的账号标识（各平台 user_id 或 username）'
  end
end
