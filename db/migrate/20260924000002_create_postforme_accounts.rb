# postforme 账号授权关联表——记录本系统账号在 postforme 的授权状态。
#
# 背景：postforme 是第三方社媒发布平台，需要先把本系统账号授权给它（OAuth），
# 拿到它在 postforme 的 social_account_id，之后发布任务才能通过 API 投递。
# 授权是一次性异步流程（拿授权 URL → 浏览器打开完成 OAuth → 轮询确认），
# 用本表记录每个账号的授权进度。一对一（account_id 唯一）。
#
# auth_status 约定：
#   0 = 未授权（默认）
#   1 = 授权中（已下发授权 URL，等待用户完成 OAuth）
#   2 = 已授权（拿到 social_account_id）
#   3 = 失败（授权失败/过期，需重新发起）
class CreatePostformeAccounts < ActiveRecord::Migration[6.1]
  def change
    create_table :postforme_accounts do |t|
      t.bigint   :account_id, null: false, comment: "本系统账号 ID（一对一）"
      t.string   :social_account_id, comment: "postforme 侧社交账号 ID（spc_xxx）"
      t.integer  :auth_status, null: false, default: 0, comment: "授权状态 0未授权 1授权中 2已授权 3失败"
      t.datetime :authorized_at, comment: "授权完成时间"

      t.timestamps
    end

    add_index :postforme_accounts, :account_id, unique: true
    add_index :postforme_accounts, :social_account_id
  end
end
