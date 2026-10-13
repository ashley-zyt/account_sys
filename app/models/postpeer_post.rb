# == Schema Information
#
# Table name: postpeer_posts
#
#  id                                                         :bigint           not null, primary key
#  error_msg(失败原因)                                        :text(65535)
#  peer_account_id(postpeer 集成 ID（冗余，便于排查）)        :string(255)
#  platform_url(发布成功后平台上的链接)                       :string(255)
#  post_id(postpeer 返回的 post ID)                           :string(255)
#  status(状态 0处理中 1成功 2失败)                           :integer          default("processing"), not null
#  task_type(本系统任务模型类名（如 MoveTask）)               :string(255)      not null
#  created_at                                                 :datetime         not null
#  updated_at                                                 :datetime         not null
#  task_id(本系统任务 ID)                                     :bigint           not null
#
# Indexes
#
#  index_postpeer_posts_on_post_id                (post_id) UNIQUE
#  index_postpeer_posts_on_status                 (status)
#  index_postpeer_posts_on_task_type_and_task_id  (task_type,task_id)
#
# postpeer 发布任务记录表模型。
#
# 记录投递给 postpeer 的每一次发布，用于轮询回写结果。
# task_type + task_id 多态关联本系统任务，post_id 关联 postpeer 侧任务。
class PostpeerPost < ApplicationRecord
  belongs_to :task, polymorphic: true, optional: true

  enum status: {
    processing: 0,
    success: 1,
    failed: 2
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[id task_type task_id post_id status platform_url peer_account_id error_msg created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[task]
  end
end
