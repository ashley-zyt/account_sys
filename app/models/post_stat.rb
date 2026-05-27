# == Schema Information
#
# Table name: post_stats
#
#  id               :bigint           not null, primary key
#  account_id       :bigint           not null
#  post_date        :date             not null
#  title            :string(255)
#  url              :string(255)
#  likes_count      :integer          default(0)
#  shares_count     :integer          default(0)
#  comments_count   :integer          default(0)
#  views_count      :integer          default(0)
#  data_updated_at  :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_post_stats_on_account_id  (account_id)
#  index_post_stats_on_post_date   (post_date)
#

class PostStat < ApplicationRecord
  belongs_to :account

  validates :account_id, presence: true
  validates :post_date, presence: true
  validates :likes_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :shares_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :comments_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :views_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_date_range, ->(start_date, end_date) { where(post_date: start_date..end_date) }
  scope :order_by_date, -> { order(post_date: :desc) }

  def self.ransackable_attributes(auth_object = nil)
    %w[
      id
      account_id
      post_date
      title
      url
      likes_count
      shares_count
      comments_count
      views_count
      data_updated_at
      created_at
      updated_at
    ]
  end

  def self.ransackable_associations(auth_object = nil)
    ["account"]
  end
end