class AddPublishChannelToTaskLogs < ActiveRecord::Migration[6.1]
  def change
    # 记录每次发布尝试实际使用的渠道（0浏览器 1postforme 2x_api），
    # 用于区分「每条发文是哪个渠道发的」以及按渠道聚合成功率/成本。
    add_column :task_logs, :publish_channel, :integer, comment: "实际发布渠道 0浏览器 1postforme 2x_api"
    add_index :task_logs, :publish_channel
  end
end
