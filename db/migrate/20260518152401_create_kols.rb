class CreateKols < ActiveRecord::Migration[6.1]
  def change
    create_table :kols do |t|
      t.string :kol_name, null: false, comment: "KOL名称"
      t.string :nick_name, comment: "昵称"
      t.string :location, comment: "地区"
      t.string :category, comment: "类别"
      t.text :notes, comment: "备注"

      t.timestamps
    end

    add_index :kols, :kol_name
    add_index :kols, :category
  end
end