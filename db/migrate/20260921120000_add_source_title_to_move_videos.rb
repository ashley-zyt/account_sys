class AddSourceTitleToMoveVideos < ActiveRecord::Migration[6.1]
  def change
    add_column :move_videos, :source_title, :string, comment: '原视频标题'
  end
end
