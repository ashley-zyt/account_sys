# == Schema Information
#
# Table name: kol_platform_accounts
#
#  id                     :bigint           not null, primary key
#  follower_count(粉丝数) :string(255)
#  nick_name(平台昵称)    :string(255)      not null
#  platform(平台)         :integer          not null
#  profile_url(主页链接)  :string(255)
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  kol_id                 :bigint           not null
#
# Indexes
#
#  index_kol_platform_accounts_on_kol_id     (kol_id)
#  index_kol_platform_accounts_on_nick_name  (nick_name)
#  index_kol_platform_accounts_on_platform   (platform)
#
# Foreign Keys
#
#  fk_rails_...  (kol_id => kols.id)
#
class KolPlatformAccount < ApplicationRecord
  belongs_to :kol

  has_many :conversations, dependent: :destroy

  enum platform: {
		facebook: 1,
		twitter: 2,
		tiktok: 3,
		youtube: 4,
		instagram: 5
	}

  validates :platform, presence: true
  validates :nick_name, presence: true
end
