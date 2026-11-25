# 允许「同一源视频在多个主题下各存一条」：source_video_url 唯一索引改为 (source_video_url, theme) 复合唯一。
# 背景：一个对标账号可能配置在多个主题下，同一批视频需要同时发布到主题 A 和主题 B，
#       原按 source_video_url 唯一会导致第二个主题入库被跳过。
class ChangeMoveVideosUniqueIndexToThemeScope < ActiveRecord::Migration[6.1]
  def up
    remove_index :move_videos, name: :idx_move_videos_source_video_url
    add_index :move_videos, [:source_video_url, :theme], unique: true,
              name: :idx_move_videos_source_video_url_theme
  end

  def down
    remove_index :move_videos, name: :idx_move_videos_source_video_url_theme
    add_index :move_videos, :source_video_url, unique: true,
              name: :idx_move_videos_source_video_url
  end
end
