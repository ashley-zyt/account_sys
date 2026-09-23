# 账号「最后采集尝试时间」——用于凌晨分批采集的退避机制。
#
# 背景：分批采集时，指纹浏览器打不开 / 页面打不开的账号数据永远不回传、永远「未获取」，
# 又按 id 排前，每轮都被选中占满配额，导致正常账号饿死。
# 加上本字段后，下发采集时记一笔时间，下一轮筛选时跳过「退避窗口内刚尝试过」的账号，
# 让正常账号有机会轮转。
class AddLastFetchAttemptedAtToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :last_fetch_attempted_at, :datetime, comment: "最后采集尝试时间（分批采集退避用）"
    add_index :accounts, :last_fetch_attempted_at
  end
end
