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
  has_many :grok_tasks
  # 仅统计有视频文件的关联任务
  has_many :video_tasks, -> { where.not(video_url: [nil, '']) }, class_name: 'GrokTask'

  validates :theme, :image_url, presence: true

  # 是否已生成过视频（存在 video_url 非空的关联 GrokTask）
  def has_video?
    video_tasks.any?
  end

  # 已生成视频数量
  def video_count
    video_tasks.size
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme image_url created_at updated_at]
  end
end
