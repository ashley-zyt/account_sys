# KOL 触达渠道切换回指纹浏览器（机器端模拟）
#
# 背景：Twitter/X API 私信方式被平台禁用，全部触达切回浏览器模拟。
#   1. 存量 x_api 渠道的联系方式（均为 twitter 平台）改为 browser，
#      包括 contacting 状态——改后回复轮询自动走机器端浏览器链路查回复
#   2. 列默认值从 x_api 改回 browser，新导入/新建的联系方式不再走 X API
#
# KolXOutreach 代码保留不删，未来 API 解禁可随时切回。
class SwitchKolContactsDefaultChannelToBrowser < ActiveRecord::Migration[6.1]
  def up
    say_with_time 'kol_contacts：x_api 渠道改回 browser' do
      KolContact.where(outreach_channel: 1).update_all(outreach_channel: 0, updated_at: Time.current)
    end
    change_column_default :kol_contacts, :outreach_channel, from: 1, to: 0
  end

  def down
    change_column_default :kol_contacts, :outreach_channel, from: 0, to: 1
  end
end
