# == Schema Information
#
# Table name: crypto_videos
#
#  id                                       :bigint           not null, primary key
#  global_crypto(加密货币全球市场数据)      :text(65535)
#  global_defi(全球 DeFi 市场数据)          :text(65535)
#  prompt(提示词)                           :text(65535)
#  result(heygen返回的结果)                 :text(65535)
#  trending(热门搜索列表)                   :text(65535)
#  video_status(视频生成状态 生成中/已完成) :string(255)
#  created_at                               :datetime         not null
#  updated_at                               :datetime         not null
#  heygen_task_id(Heygen任务ID)             :integer
#  video_id(视频ID)                         :string(255)
#
# Indexes
#
#  index_crypto_videos_on_heygen_task_id  (heygen_task_id)
#  index_crypto_videos_on_video_id        (video_id)
#  index_crypto_videos_on_video_status    (video_status)
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
