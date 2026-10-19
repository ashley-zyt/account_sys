# == Schema Information
#
# Table name: comment_tasks
#
#  id                 :bigint           not null, primary key
#  comment_content    :text(65535)
#  error_msg          :text(65535)
#  executed_at        :datetime
#  machine_task_id    :string(255)
#  status             :integer          default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint            not null
#  influencer_post_id :bigint            not null
#
# Indexes
#
#  index_comment_tasks_on_account_id                          (account_id)
#  index_comment_tasks_on_influencer_post_id_and_account_id   (influencer_post_id,account_id) UNIQUE
#  index_comment_tasks_on_status                              (status)
#
class CommentTask < ApplicationRecord
  belongs_to :influencer_post
  belongs_to :account

  enum status: {
    pending: 0,   # 待评论（已生成内容，未下发）
    queued: 1,    # 已下发（等机器端受理）
    running: 2,   # 执行中
    success: 3,   # 评论成功
    failed: 4     # 评论失败
  }

  def self.ransackable_attributes(auth_object = nil)
    %w[id influencer_post_id account_id status machine_task_id error_msg executed_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[influencer_post account]
  end
end
