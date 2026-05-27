class CreateThemesTable < ActiveRecord::Migration[6.1]
  def change
    create_table :themes do |t|
      t.string :name, null: false
      t.string :oss_directory
      t.text :titles
      t.text :remark

      t.timestamps
    end

    add_index :themes, :name, unique: true
    add_index :themes, :oss_directory, unique: true
  end
end
