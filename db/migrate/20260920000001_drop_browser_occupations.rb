# 移除浏览器占用中心（browser_occupations）机制
#
# 背景：之前引入的「占用中心」用于系统内自己管理「每机器最多 N 个浏览器 + 同浏览器互斥」，
# 后来发文/养号/采集全部改为机器端 async 模式（机器端自己管并发 + profile 锁 + 完成后回传），
# KOL / 抖音/视频号也不再走占用中心，这套机制已无调用方，故整体移除。
class DropBrowserOccupations < ActiveRecord::Migration[6.1]
  def change
    drop_table :browser_occupations, if_exists: true
  end
end
