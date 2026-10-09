# == Schema Information
#
# Table name: x_posts
#
#  id         :bigint           not null, primary key
#  error_msg  :text(65535)
#  media_id   :string(255)
#  status     :integer          default("processing"), not null
#  task_type  :string(255)      not null
#  tweet_id   :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  task_id    :bigint           not null
#
# Indexes
#
#  index_x_posts_on_media_id         (media_id)
#  index_x_posts_on_status           (status)
#  index_x_posts_on_task_type_and_task_id  (task_type,task_id)
#
# X（Twitter）API 发布任务记录表模型。
#
# 记录投递给 X API 的每一次发布（视频上传 + 发推），用于轮询回写结果。
# task_type + task_id 多态关联本系统任务（MoveTask/HunjianTask/JianyingTask 等），
# media_id 关联 X 侧媒体，tweet_id 关联 X 侧推文，status 是本系统视角的终态。
class XPost < ApplicationRecord
  # 多态关联本系统任务（各资源队列 Model）
  belongs_to :task, polymorphic: true, optional: true

  # status：processing=已上传待处理 / success=发布成功 / failed=发布失败
  enum status: {
    processing: 0,
    success: 1,
    failed: 2
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[id task_type task_id media_id tweet_id status error_msg created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[task]
  end
end
