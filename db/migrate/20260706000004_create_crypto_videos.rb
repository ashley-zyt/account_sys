class CreateCryptoVideos < ActiveRecord::Migration[6.1]
  def change
    create_table :crypto_videos do |t|
      t.text :global_crypto, comment: '加密货币全球市场数据'
      t.text :global_defi, comment: '全球 DeFi 市场数据'
      t.text :trending, comment: '热门搜索列表'
      t.text :prompt, comment: '提示词'
      t.string :video_id, comment: '视频ID'
      t.string :video_status, comment: '视频生成状态 生成中/已完成'
      t.text :result, comment: 'heygen返回的结果'

      t.timestamps
    end

    add_index :crypto_videos, :video_id
    add_index :crypto_videos, :video_status
  end
end