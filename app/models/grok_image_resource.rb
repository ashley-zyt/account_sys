# == Schema Information
#
# Table name: grok_image_resources
#
#  id         :bigint           not null, primary key
#  image_url  :string(255)
#  theme      :string(255)
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_grok_image_resources_on_theme  (theme)
#
class GrokImageResource < ApplicationRecord
  has_one :grok_video_resource

  validates :theme, :image_url, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme image_url created_at updated_at]
  end
end
