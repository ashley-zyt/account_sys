# == Schema Information
#
# Table name: grok_image_resources
#
#  id         :bigint           not null, primary key
#  image_name :string(255)
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
  has_many :grok_tasks, foreign_key: :grok_image_id
  # 仅统计有视频文件的关联任务
  has_many :video_tasks, -> { where.not(video_url: [nil, '']) }, class_name: 'GrokTask', foreign_key: :grok_image_id

  validates :theme, :image_url, presence: true

  # 是否已生成过视频（存在 video_url 非空的关联 GrokTask）
  def has_video?
    video_tasks.any?
  end

  # 已生成视频数量（按 video_url 去重）
  def video_count
    distinct_video_urls.size
  end

  # 去重后的 video_url 列表
  def distinct_video_urls
    @distinct_video_urls ||= video_tasks.map(&:video_url).compact_blank.uniq
  end

  # 用于前端弹窗展示的视频任务列表（按 video_url 去重，每项包含 url 和关联的平台 + 状态）
  def video_task_list
    @video_task_list ||= begin
      grouped = video_tasks.group_by(&:video_url).compact_blank
      grouped.map do |url, tasks|
        {
          url: url,
          platforms: tasks.map { |t| { name: t.platform, status: t.status, task_id: t.id } }
        }
      end
    end
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[id theme image_url image_name created_at updated_at]
  end
end
