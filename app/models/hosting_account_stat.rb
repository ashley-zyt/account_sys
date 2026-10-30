# == Schema Information
#
# Table name: hosting_account_stats
#
#  id                             :bigint           not null, primary key
#  followers_count(粉丝数)        :bigint
#  snapshot_at(快照时间)          :datetime
#  stat_date(统计日期)            :date             not null
#  total_comments(总评论数)       :bigint
#  total_likes(总点赞数)          :bigint
#  total_posts(发帖数)            :bigint
#  total_shares(总分享数)         :bigint
#  total_views(总浏览量)          :bigint
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  hosting_account_id(托管账号ID) :bigint           not null
#
# Indexes
#
#  index_hosting_account_stats_on_account_and_date  (hosting_account_id,stat_date) UNIQUE
#  index_hosting_account_stats_on_stat_date         (stat_date)
#
class HostingAccountStat < ApplicationRecord
  belongs_to :hosting_account

  def self.ransackable_attributes(auth_object = nil)
    %w[id hosting_account_id stat_date followers_count total_posts total_views total_likes total_comments total_shares snapshot_at created_at]
  end

  def self.ransackable_associations(auth_object = nil)
    %w[hosting_account]
  end
end
