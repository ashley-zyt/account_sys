class ChangePublishChannelNullableOnAccounts < ActiveRecord::Migration[6.1]
  def change
    # publish_channel 语义由「唯一发布渠道」改为「首选渠道」：
    # 允许为空（空 = 走平台默认链），现有值原样保留。
    change_column :accounts, :publish_channel, :integer, null: true, default: nil
  end
end
