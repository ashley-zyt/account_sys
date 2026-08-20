class CreateLanguages < ActiveRecord::Migration[6.1]
  def change
    create_table :languages do |t|
      t.string :code, null: false, comment: "语言代码（zh/en/ja…）"
      t.string :name, null: false, comment: "语言中文名"
      t.timestamps
    end

    add_index :languages, :code, unique: true
  end
end
