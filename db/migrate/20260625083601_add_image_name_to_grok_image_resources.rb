class AddImageNameToGrokImageResources < ActiveRecord::Migration[6.1]
  def change
    add_column :grok_image_resources, :image_name, :string
  end
end
