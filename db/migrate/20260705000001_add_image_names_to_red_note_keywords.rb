class AddImageNamesToRedNoteKeywords < ActiveRecord::Migration[6.1]
  def change
    add_column :red_note_keywords, :image_names, :text, comment: "采集到的图片名称列表（JSON数组）"
  end
end
