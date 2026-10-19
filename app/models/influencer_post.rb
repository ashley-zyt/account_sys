# == Schema Information
#
# Table name: influencer_posts
#
#  id            :bigint           not null, primary key
#  title         :text(65535)
#  posted_at     :datetime
#  post_id       :string(255)      not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  influencer_id :bigint            not null
#
# Indexes
#
#  index_influencer_posts_on_influencer_id  (influencer_id)
#  index_influencer_posts_on_post_id        (post_id) UNIQUE
#
class InfluencerPost < ApplicationRecord
  belongs_to :influencer
  has_many :comment_tasks, dependent: :destroy

  validates :post_id, presence: true, uniqueness: true

  # 该发文是否已被指定账号评论过（或已生成评论任务）
  def commented_by?(account_id)
    comment_tasks.exists?(account_id: account_id)
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id influencer_id post_id title posted_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[influencer comment_tasks]
  end
end
