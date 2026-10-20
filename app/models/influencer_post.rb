# == Schema Information
#
# Table name: influencer_posts
#
#  id                  :bigint           not null, primary key
#  posted_at(发文时间) :datetime
#  source_url(发文链接) :string(255)
#  title(标题/内容)    :text(65535)
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  influencer_id(大V)  :bigint           not null
#  post_id(发文 ID)    :string(255)      not null
#
# Indexes
#
#  index_influencer_posts_on_influencer_id  (influencer_id)
#  index_influencer_posts_on_post_id        (post_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (influencer_id => influencers.id)
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
    %w[id influencer_id post_id title source_url posted_at created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[influencer comment_tasks]
  end
end
