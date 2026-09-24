# postforme 发布任务记录表——记录投递给 postforme 的每一次发布，用于轮询回写结果。
#
# 背景：postforme 发布是「提交任务 → 返回 post ID → 异步处理 → 查询结果」的拉模式。
# account_sys 提交发布后，需要定时轮询 postforme 查询 post 状态，并把结果回写到本系统任务。
# 本表用 task_type + task_id 多态关联本系统任务（MoveTask/HunjianTask/JianyingTask 等），
# post_id 关联 postforme 侧任务。
#
# status 约定（本系统视角的终态）：
#   0 = processing（已提交，postforme 处理中，尚未确认结果）
#   1 = success（postforme 已发布成功）
#   2 = failed（postforme 发布失败）
class CreatePostformePosts < ActiveRecord::Migration[6.1]
  def change
    create_table :postforme_posts do |t|
      t.string   :task_type, null: false, comment: "本系统任务模型类名（如 MoveTask）"
      t.bigint   :task_id, null: false, comment: "本系统任务 ID"
      t.string   :post_id, comment: "postforme 返回的 post ID"
      t.integer  :status, null: false, default: 0, comment: "状态 0处理中 1成功 2失败"
      t.string   :platform_url, comment: "发布成功后平台上的链接"
      t.string   :social_account_id, comment: "postforme 社交账号 ID（冗余，便于排查）"
      t.text     :error_msg, comment: "失败原因"

      t.timestamps
    end

    add_index :postforme_posts, [:task_type, :task_id]
    add_index :postforme_posts, :post_id, unique: true
    add_index :postforme_posts, :status
  end
end
