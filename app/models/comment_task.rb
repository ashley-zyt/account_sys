# == Schema Information
#
# Table name: comment_tasks
#
#  id                                               :bigint           not null, primary key
#  comment_content(生成的评论内容)                  :text(65535)
#  error_msg(失败原因)                              :text(65535)
#  executed_at(执行时间)                            :datetime
#  status(状态 0待评论 1已下发 2执行中 3成功 4失败) :integer          default("pending"), not null
#  created_at                                       :datetime         not null
#  updated_at                                       :datetime         not null
#  account_id(评论账号)                             :bigint           not null
#  influencer_post_id(大V发文)                      :bigint           not null
#  machine_task_id(机器端任务 ID)                   :string(255)
#
# Indexes
#
#  index_comment_tasks_on_account_id                         (account_id)
#  index_comment_tasks_on_influencer_post_id                 (influencer_post_id)
#  index_comment_tasks_on_influencer_post_id_and_account_id  (influencer_post_id,account_id) UNIQUE
#  index_comment_tasks_on_status                             (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (influencer_post_id => influencer_posts.id)
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
