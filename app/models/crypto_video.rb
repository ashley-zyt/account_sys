# == Schema Information
#
# Table name: crypto_videos
#
#  id            :bigint           not null, primary key
#  global_crypto :text(65535)      comment: '加密货币全球市场数据'
#  global_defi   :text(65535)      comment: '全球 DeFi 市场数据'
#  trending      :text(65535)      comment: '热门搜索列表'
#  prompt        :text(65535)      comment: '提示词'
#  video_id      :string(255)      comment: '视频ID'
#  video_status  :string(255)      comment: '视频生成状态 生成中/已完成'
#  result        :text(65535)      comment: 'heygen返回的结果'
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class CryptoVideo < ApplicationRecord
  has_many :heygen_tasks, foreign_key: :templete_id, primary_key: :video_id

  scope :generating, -> { where(video_status: '生成中') }
  scope :completed, -> { where(video_status: '已完成') }

  def global_crypto_data
    JSON.parse(global_crypto) rescue {}
  end

  def global_defi_data
    JSON.parse(global_defi) rescue {}
  end

  def trending_data
    JSON.parse(trending) rescue []
  end

  def result_data
    JSON.parse(result) rescue {}
  end
end