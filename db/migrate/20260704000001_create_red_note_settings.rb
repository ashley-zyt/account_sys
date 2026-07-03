class CreateRedNoteSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :red_note_settings do |t|
      t.integer :search_max_results, default: 20, null: false, comment: "搜索结果前N条帖子"
      t.integer :top_n_by_likes,     default: 3,  null: false, comment: "前N条帖子里按点赞量排序取前M条"
      t.timestamps
    end
  end
end
