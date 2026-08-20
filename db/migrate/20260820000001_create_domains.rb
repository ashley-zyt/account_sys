class CreateDomains < ActiveRecord::Migration[6.1]
  def change
    create_table :domains do |t|
      t.string :name, null: false, comment: "领域名称（文旅/金融/科技…）"
      t.timestamps
    end

    add_index :domains, :name, unique: true
  end
end
