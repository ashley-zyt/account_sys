# 每日账号发布对账快照表。
#
# 每天定时（config/schedule.rb 21:30）遍历所有未删除账号，计算每个账号当天
# 「是否发布 + 未发布原因」并落库，供日后回溯对账（如「某天发布数字对不上」时按日期查）。
#
# 一条记录 = 一个账号某一天的发布结果。
# result 语义见 AccountPublishDaily 模型。
class CreateAccountPublishDailies < ActiveRecord::Migration[6.1]
  def change
    create_table :account_publish_dailies, comment: '每日账号发布对账快照' do |t|
      t.date     :stat_date,   null: false, comment: '统计日期'
      t.bigint   :account_id,  null: false, comment: '账号ID'
      t.integer  :platform,    comment: '平台快照（accounts.platform 枚举值）'
      t.string   :theme,       comment: '主题快照'
      t.string   :work_type,   comment: '工作模式快照（中文名）'
      t.integer  :result,      null: false, comment: '发布结果 0成功 1失败 2agent 3封禁 4tiktok低浏览 5资源不足 6无浏览器 7有资源未发布'
      t.string   :reason,      comment: '未发布/失败原因文本'
      t.text     :error_msg,   comment: '失败时的具体错误信息'
      t.bigint   :task_log_id, comment: '关联当天该账号的 task_log（可空）'

      t.timestamps
    end

    add_index :account_publish_dailies, [:stat_date, :account_id], unique: true
    add_index :account_publish_dailies, [:stat_date, :result]
    add_index :account_publish_dailies, [:stat_date, :platform]
    add_index :account_publish_dailies, :account_id
  end
end
