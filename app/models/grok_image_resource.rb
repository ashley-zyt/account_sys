class GrokImageResource < ApplicationRecord
  has_one :grok_video_resource

  validates :theme, :image_url, presence: true

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme image_url created_at updated_at]
  end
end