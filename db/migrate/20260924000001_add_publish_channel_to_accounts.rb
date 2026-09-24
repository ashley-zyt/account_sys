# 账号「发布渠道」标记——决定发布执行走哪条链路。
#
# 背景：接入 postforme 第三方平台后，部分账号的发布不再走 ag_center 指纹浏览器模拟，
# 而是通过 postforme API 发布。用本字段标记每个账号走哪条渠道，便于灰度切换与后续扩展
# 其它发布模式（如再接入别的平台）。
#
# 值约定：
#   0 = ag_center（默认，原有指纹浏览器模拟发布）
#   1 = postforme（第三方平台 API 发布）
class AddPublishChannelToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :publish_channel, :integer, null: false, default: 0, comment: "发布渠道 0=ag_center 1=postforme"
    add_index :accounts, :publish_channel
  end
end
