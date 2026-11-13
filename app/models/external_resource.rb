# == Schema Information
#
# Table name: external_resources
#
#  id         :bigint           not null, primary key
#  theme      :string(255)      not null
#  source     :integer          default("grok_bot"), not null
#  media_type :integer          default("image"), not null
#  text       :text(65535)
#  media_urls :text(65535)      # JSON 数组
#  platforms  :text(65535)      # JSON 数组
#  status     :integer          default("pending"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class ExternalResource < ApplicationRecord
  serialize :media_urls, JSON
  serialize :platforms, JSON

  has_many :external_publish_tasks, dependent: :destroy

  # 来源：先只有 grok_bot，未来扩展 manual/其他渠道只需加枚举值
  enum source: {
    grok_bot: 0
  }

  # 媒体形态：主媒体类型（text 字段独立，可与任意媒体形态组合）
  enum media_type: {
    video: 0,
    image: 1,
    text: 2
  }

  enum status: {
    pending: 0,       # 待生成发布任务
    queued: 1,        # 已生成发布任务
    published: 2,     # 已发布
    failed: 3         # 失败
  }

  validates :theme, presence: true

  def media_urls
    super || []
  end

  def platforms
    super || []
  end
end
