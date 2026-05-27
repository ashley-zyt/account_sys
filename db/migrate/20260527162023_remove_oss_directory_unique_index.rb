class RemoveOssDirectoryUniqueIndex < ActiveRecord::Migration[6.1]
  def change
    remove_index :themes, :oss_directory
    add_index :themes, :oss_directory, unique: true, where: 'oss_directory IS NOT NULL'
  end
end
