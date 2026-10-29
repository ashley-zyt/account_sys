# 账号变更/异常记录表。
#
# 一条记录 = 账号的一次字段/状态变更，或一次系统自动检测到的异常（封禁/未登录/网络等）。
# - change_source 区分「系统自动 / 人工」
# - abnormal_type 细分异常类型（仅系统自动时填，人工为 null）
# - changes_json 存字段级变更明细 [{field, from, to}]
class CreateAccountChangeLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :account_change_logs, comment: '账号变更/异常记录' do |t|
      t.bigint   :account_id,      null: false, comment: '账号ID'
      t.integer  :change_source,   null: false, comment: '变更来源 0系统自动 1人工'
      t.integer  :abnormal_type,   comment: '异常类型 0封禁/限制 1未登录 2网络 3其他（仅系统自动）'
      t.string   :operator,        comment: '更改人/操作人（人工）'
      t.string   :change_reason,   comment: '变更原因'
      t.text     :changes_json,    comment: '字段级变更明细 [{field, from, to}]'
      t.string   :source_action,   comment: '发现动作：发布/采集/私信/养号/登录检查'
      t.string   :matched_keyword, comment: '命中的关键词'
      t.text     :error_msg,       comment: '完整错误信息'
      t.string   :screenshot_url,  comment: '截图 OSS URL'
      t.datetime :changed_at,      comment: '变更/发现时间'

      t.timestamps
    end

    add_index :account_change_logs, :account_id
    add_index :account_change_logs, :change_source
    add_index :account_change_logs, :abnormal_type
    add_index :account_change_logs, :changed_at
  end
end
