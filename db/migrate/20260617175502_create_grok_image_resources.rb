class CreateGrokImageResources < ActiveRecord::Migration[6.1]
  def change
    create_table :grok_image_resources do |t|
      t.string :theme
      t.string :image_url

      t.timestamps
    end
    add_index :grok_image_resources, :theme
  end
end