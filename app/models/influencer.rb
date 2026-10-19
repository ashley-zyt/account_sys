# == Schema Information
#
# Table name: influencers
#
#  id                                             :bigint           not null, primary key
#  enabled(是否启用)                              :boolean          default(TRUE), not null
#  platform(平台（twitter/youtube/instagram 等）) :string(255)      default("twitter"), not null
#  remark(备注)                                   :text(65535)
#  username(用户名)                               :string(255)      not null
#  created_at                                     :datetime         not null
#  updated_at                                     :datetime         not null
#  domain_id(所属领域)                            :bigint
#  user_id(平台用户 ID)                           :string(255)
#
# Indexes
#
#  index_influencers_on_domain_id  (domain_id)
#  index_influencers_on_username   (username) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (domain_id => domains.id)
#
class Influencer < ApplicationRecord
  belongs_to :domain, optional: true
  has_many :influencer_posts, dependent: :destroy

  validates :username, presence: true, uniqueness: true

  scope :enabled, -> { where(enabled: true) }

  def self.ransackable_attributes(auth_object = nil)
    %w[id username user_id platform domain_id enabled remark created_at updated_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[domain influencer_posts]
  end
end
