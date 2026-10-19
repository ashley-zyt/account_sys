# == Schema Information
#
# Table name: influencers
#
#  id         :bigint           not null, primary key
#  enabled    :boolean          default(TRUE), not null
#  platform   :string(255)      default("twitter"), not null
#  remark     :text(65535)
#  user_id    :string(255)
#  username   :string(255)      not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  domain_id  :bigint
#
# Indexes
#
#  index_influencers_on_domain_id  (domain_id)
#  index_influencers_on_username   (username) UNIQUE
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
