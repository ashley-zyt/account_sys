# == Schema Information
#
# Table name: x_posts
#
#  id                                           :bigint           not null, primary key
#  error_msg(失败原因)                          :text(65535)
#  status(状态 0处理中 1成功 2失败)             :integer          default("processing"), not null
#  task_type(本系统任务模型类名（如 MoveTask）) :string(255)      not null
#  created_at                                   :datetime         not null
#  updated_at                                   :datetime         not null
#  media_id(X 侧 media id)                      :string(255)
#  task_id(本系统任务 ID)                       :bigint           not null
#  tweet_id(X 侧 tweet id（发推成功后写入）)    :string(255)
#
# Indexes
#
#  index_x_posts_on_media_id               (media_id)
#  index_x_posts_on_status                 (status)
#  index_x_posts_on_task_type_and_task_id  (task_type,task_id)
#
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
