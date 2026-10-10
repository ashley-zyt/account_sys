class AddPublishChannelToPostStats < ActiveRecord::Migration[6.1]
  def change
    # 发文统计的实际发布渠道（0浏览器 1postforme 2x_api），精确到每条发文。
    # 采集时按 url 反查回填；匹配不到留空。
    add_column :post_stats, :publish_channel, :integer, comment: "实际发布渠道 0浏览器 1postforme 2x_api"
    add_index :post_stats, :publish_channel
  end
end
