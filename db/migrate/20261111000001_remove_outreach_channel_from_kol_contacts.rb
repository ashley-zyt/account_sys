# KOL 触达模块治理：删除已失效的 outreach_channel 字段。
#
# 背景：早期 X API 私信刚接入时，用该字段标记每个 twitter 联系方式走「指纹浏览器」还是「X API」。
# 后经多次切换（X API 禁用→切浏览器→又切回 X API），通道决策已收敛为「由平台本身决定」：
#   twitter → X API，其它 → 浏览器（见 KolContact#x_api_channel?）。
# 该字段已无任何代码读取，是纯误导源，故删除。
class RemoveOutreachChannelFromKolContacts < ActiveRecord::Migration[6.1]
  def change
    remove_column :kol_contacts, :outreach_channel, :integer
  end
end
