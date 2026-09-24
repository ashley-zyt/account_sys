# postforme 发布任务记录表模型。
#
# 记录投递给 postforme 的每一次发布，用于轮询回写结果。
# task_type + task_id 多态关联本系统任务（MoveTask/HunjianTask/JianyingTask 等），
# post_id 关联 postforme 侧任务，status 是本系统视角的终态。
class PostformePost < ApplicationRecord
  # 多态关联本系统任务（各资源队列 Model）
  belongs_to :task, polymorphic: true, optional: true

  # status：processing=已提交处理中 / success=发布成功 / failed=发布失败
  enum status: {
    processing: 0,
    success: 1,
    failed: 2
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[id task_type task_id post_id status platform_url social_account_id error_msg created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[task]
  end
end
