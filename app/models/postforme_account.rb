# postforme 账号授权关联表模型。
#
# 记录本系统账号在 postforme 平台的授权状态与社交账号 ID。
# 授权是一次性异步流程（拿授权 URL → 浏览器完成 OAuth → 轮询确认），本模型承载其状态机。
class PostformeAccount < ApplicationRecord
  belongs_to :account

  # 授权状态：pending=未授权 / authorizing=授权中 / authorized=已授权 / failed=失败
  enum auth_status: {
    pending: 0,
    authorizing: 1,
    authorized: 2,
    failed: 3
  }

  # 是否已成功授权（授权完成且已拿到 social_account_id）
  def authorized?
    auth_status == "authorized" && social_account_id.present?
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id account_id social_account_id auth_status authorized_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[account]
  end
end
